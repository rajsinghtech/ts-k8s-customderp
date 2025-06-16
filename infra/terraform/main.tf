# Get availability zones
data "aws_availability_zones" "available" {
  state = "available"
}

# Get default VPC
data "aws_vpc" "default" {
  default = true
}

# Get default subnets
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security group for EKS nodes with DERP and ICMP access
resource "aws_security_group" "node_group_sg" {
  name_prefix = "${var.cluster_name}-node-sg"
  vpc_id      = data.aws_vpc.default.id
  description = "Security group for EKS nodes with DERP and ICMP access"

  # ICMP (ping) traffic
  ingress {
    description = "ICMP traffic"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH access
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # DERP HTTP port
  ingress {
    description = "DERP HTTP"
    from_port   = var.derp_http_port
    to_port     = var.derp_http_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # DERP HTTPS port
  ingress {
    description = "DERP HTTPS"
    from_port   = var.derp_https_port
    to_port     = var.derp_https_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # DERP STUN port (TCP)
  ingress {
    description = "DERP STUN TCP"
    from_port   = var.derp_stun_port
    to_port     = var.derp_stun_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # DERP STUN port (UDP)
  ingress {
    description = "DERP STUN UDP"
    from_port   = var.derp_stun_port
    to_port     = var.derp_stun_port
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-node-sg"
  }
}

# EKS Cluster using the terraform-aws-modules/eks/aws module
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = data.aws_vpc.default.id
  subnet_ids = data.aws_subnets.default.ids

  # Enable OIDC identity provider
  enable_irsa = true

  # EKS Managed Node Groups
  eks_managed_node_groups = {
    ng-cluster = {
      name           = "ng-cluster"
      instance_types = [var.instance_type]

      min_size     = var.min_size
      max_size     = var.max_size
      desired_size = var.desired_capacity

      # Use public subnets (equivalent to privateNetworking: false)
      subnet_ids = data.aws_subnets.default.ids

      # Enable SSH access
      remote_access = {
        ec2_ssh_key = var.key_name
      }

      # Add our custom security group
      vpc_security_group_ids = [aws_security_group.node_group_sg.id]

      # Update configuration
      update_config = {
        max_unavailable = 2
      }

      tags = {
        Name = "${var.cluster_name}-ng-cluster"
      }
    }
  }

  # Cluster access entry
  access_entries = {
    cluster = {
      kubernetes_groups = []
      principal_arn     = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"

      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  tags = {
    Name        = var.cluster_name
    Environment = "dev"
  }
}

# Get current AWS caller identity
data "aws_caller_identity" "current" {}

# EKS add-ons
resource "aws_eks_addon" "coredns" {
  cluster_name = module.eks.cluster_name
  addon_name   = "coredns"
  depends_on   = [module.eks]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = module.eks.cluster_name
  addon_name   = "kube-proxy"
  depends_on   = [module.eks]
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = module.eks.cluster_name
  addon_name   = "vpc-cni"
  depends_on   = [module.eks]
} 