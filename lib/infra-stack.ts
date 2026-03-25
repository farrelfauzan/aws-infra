import * as cdk from "aws-cdk-lib/core";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as ecr from "aws-cdk-lib/aws-ecr";
import * as iam from "aws-cdk-lib/aws-iam";
import { Construct } from "constructs";

export class InfraStack extends cdk.Stack {
  public readonly instance: ec2.Instance;
  public readonly instanceSecurityGroup: ec2.SecurityGroup;
  public readonly vpc: ec2.IVpc;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // -------------------------------------------------------
    // VPC — use default VPC (no cost, no NAT Gateway)
    // -------------------------------------------------------
    this.vpc = ec2.Vpc.fromLookup(this, "DefaultVpc", {
      isDefault: true,
    });

    // -------------------------------------------------------
    // ECR Repositories — one per service
    // -------------------------------------------------------
    const serviceNames = [
      "api-gateway",
      "auth-service",
      "content-service",
      "customer-service",
      "student-service",
      "hls-api",
      "hls-worker",
      "performa-studio",
    ];

    const repositories = serviceNames.map(
      (name) =>
        new ecr.Repository(this, `Ecr-${name}`, {
          repositoryName: `performa-dev/${name}`,
          removalPolicy: cdk.RemovalPolicy.DESTROY,
          emptyOnDelete: true,
          lifecycleRules: [
            {
              maxImageCount: 3,
              description: "Keep only 3 most recent images",
            },
          ],
        }),
    );

    // -------------------------------------------------------
    // Security Group
    // -------------------------------------------------------
    this.instanceSecurityGroup = new ec2.SecurityGroup(this, "InstanceSg", {
      vpc: this.vpc,
      description: "Security group for EC2 instance",
      allowAllOutbound: true,
    });

    this.instanceSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      "Allow HTTP",
    );

    this.instanceSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      "Allow HTTPS",
    );

    this.instanceSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(22),
      "Allow SSH",
    );

    // -------------------------------------------------------
    // IAM Role — SSM + ECR pull access
    // -------------------------------------------------------
    const role = new iam.Role(this, "InstanceRole", {
      assumedBy: new iam.ServicePrincipal("ec2.amazonaws.com"),
      description: "EC2 instance role with SSM and ECR access",
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName(
          "AmazonSSMManagedInstanceCore",
        ),
      ],
    });

    // Grant ECR pull to instance
    repositories.forEach((repo) => repo.grantPull(role));

    // ECR auth token (needed for docker login)
    role.addToPolicy(
      new iam.PolicyStatement({
        actions: ["ecr:GetAuthorizationToken"],
        resources: ["*"],
      }),
    );

    // -------------------------------------------------------
    // SSH Key Pair
    // -------------------------------------------------------
    const keyPair = new ec2.KeyPair(this, "AppKeyPair", {
      keyPairName: "app-instance-key",
      type: ec2.KeyPairType.ED25519,
    });

    // -------------------------------------------------------
    // UserData — install Docker, Compose, Nginx on first boot
    // -------------------------------------------------------
    const userData = ec2.UserData.forLinux();
    userData.addCommands(
      "#!/bin/bash",
      "set -euxo pipefail",

      // Swap (2GB) — safety net for memory spikes
      "fallocate -l 2G /swapfile",
      "chmod 600 /swapfile",
      "mkswap /swapfile",
      "swapon /swapfile",
      'echo "/swapfile swap swap defaults 0 0" >> /etc/fstab',

      // Docker
      "apt-get update -y",
      "apt-get install -y ca-certificates curl gnupg",
      "install -m 0755 -d /etc/apt/keyrings",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg",
      "chmod a+r /etc/apt/keyrings/docker.gpg",
      'echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list',
      "apt-get update -y",
      "apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin",
      "systemctl enable docker",
      "usermod -aG docker ubuntu",

      // ECR credential helper (no more `docker login` needed)
      "apt-get install -y amazon-ecr-credential-helper",
      "mkdir -p /home/ubuntu/.docker",
      'echo \'{"credsStore": "ecr-login"}\' > /home/ubuntu/.docker/config.json',
      "chown -R ubuntu:ubuntu /home/ubuntu/.docker",

      // Nginx
      "apt-get install -y nginx",
      "systemctl enable nginx",

      // AWS CLI
      "apt-get install -y awscli",

      // App directory
      "mkdir -p /opt/performa",
      "chown ubuntu:ubuntu /opt/performa",
    );

    // -------------------------------------------------------
    // EC2 Instance — t3.small, Ubuntu 24.04 LTS, gp3 25GB
    // -------------------------------------------------------
    this.instance = new ec2.Instance(this, "AppInstance", {
      vpc: this.vpc,
      instanceName: "performa-dev",
      vpcSubnets: { subnetType: ec2.SubnetType.PUBLIC },
      instanceType: ec2.InstanceType.of(
        ec2.InstanceClass.T3,
        ec2.InstanceSize.SMALL,
      ),
      machineImage: ec2.MachineImage.lookup({
        name: "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*",
        owners: ["099720109477"], // Canonical
      }),
      securityGroup: this.instanceSecurityGroup,
      role,
      keyPair,
      userData,
      blockDevices: [
        {
          deviceName: "/dev/sda1",
          volume: ec2.BlockDeviceVolume.ebs(25, {
            volumeType: ec2.EbsDeviceVolumeType.GP3,
            encrypted: true,
          }),
        },
      ],
      requireImdsv2: true,
    });

    // -------------------------------------------------------
    // Elastic IP
    // -------------------------------------------------------
    const eip = new ec2.CfnEIP(this, "InstanceEip", {
      domain: "vpc",
    });

    new ec2.CfnEIPAssociation(this, "EipAssociation", {
      eip: eip.ref,
      instanceId: this.instance.instanceId,
    });

    // -------------------------------------------------------
    // Outputs
    // -------------------------------------------------------
    new cdk.CfnOutput(this, "InstanceId", {
      value: this.instance.instanceId,
      description: "EC2 Instance ID",
    });

    new cdk.CfnOutput(this, "PublicIp", {
      value: eip.attrPublicIp,
      description: "Elastic IP address",
    });

    new cdk.CfnOutput(this, "SsmConnectCommand", {
      value: `aws ssm start-session --target ${this.instance.instanceId}`,
      description: "SSM Session Manager connect command",
    });

    new cdk.CfnOutput(this, "EcrLoginCommand", {
      value: `aws ecr get-login-password --region ${this.region} | docker login --username AWS --password-stdin ${this.account}.dkr.ecr.${this.region}.amazonaws.com`,
      description: "ECR login command",
    });
  }
}
