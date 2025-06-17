locals {
  name = var.cluster_name

  aws_tags = {
    Name = local.name
    Terraform = "true"
  }

  # EKS cluster configuration
  cluster_version    = var.cluster_version
  node_instance_type = var.instance_type
  node_capacity_type = "ON_DEMAND"
  node_ami_type      = "AL2023_x86_64_STANDARD"
  desired_size       = var.desired_capacity
  max_size           = var.max_size
  min_size           = var.min_size

  # Tailscale configuration
  tailscale_oauth_client_id     = var.tailscale_oauth_client_id
  tailscale_oauth_client_secret = var.tailscale_oauth_client_secret
}

# Get availability zones (exclude us-east-1e which doesn't support EKS)
data "aws_availability_zones" "available" {
  state = "available"
  exclude_names = ["us-east-1e"]
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# Get default VPC
data "aws_vpc" "default" {
  default = true
}

# Get default subnets in supported AZs only
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "availability-zone"
    values = data.aws_availability_zones.available.names
  }
}

# Get detailed subnet information to check public IP assignment
data "aws_subnet" "default_subnets" {
  for_each = toset(data.aws_subnets.default.ids)
  id       = each.value
}

# EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = local.name
  role_arn = aws_iam_role.cluster.arn
  version  = local.cluster_version

  vpc_config {
    subnet_ids              = data.aws_subnets.default.ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["0.0.0.0/0"]
    security_group_ids      = [aws_security_group.cluster.id, aws_security_group.derp_nodes.id]
  }

  # Enable logging
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = local.aws_tags

  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
    aws_cloudwatch_log_group.eks_cluster,
  ]
}

# EKS Node Group
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.name}-nodes"
  node_role_arn   = aws_iam_role.node_group.arn
  subnet_ids      = data.aws_subnets.default.ids

  capacity_type  = local.node_capacity_type
  ami_type       = local.node_ami_type
  instance_types = [local.node_instance_type]

  scaling_config {
    desired_size = local.desired_size
    max_size     = local.max_size
    min_size     = local.min_size
  }

  update_config {
    max_unavailable = 1
  }

  # SSH access configuration
  remote_access {
    ec2_ssh_key               = var.key_name
    source_security_group_ids = [aws_security_group.derp_nodes.id]
  }

  tags = local.aws_tags

  depends_on = [
    aws_iam_role_policy_attachment.node_group_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.node_group_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.node_group_AmazonEC2ContainerRegistryReadOnly,
  ]
}

# CloudWatch Log Group for EKS Cluster
resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${local.name}/cluster"
  retention_in_days = 7
  tags              = local.aws_tags
}

# Kubernetes namespace for Tailscale operator
resource "kubernetes_namespace" "tailscale_operator" {
  metadata {
    name = "tailscale"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }

  depends_on = [aws_eks_node_group.main]
}

# Deploy Tailscale Operator using Helm
resource "helm_release" "tailscale_operator" {
  name       = "tailscale-operator"
  repository = "https://pkgs.tailscale.com/helmcharts"
  chart      = "tailscale-operator"
  version    = "1.84.0"
  namespace  = kubernetes_namespace.tailscale_operator.metadata[0].name

  values = [
    yamlencode({
      operatorConfig = {
        image = {
          repo = "tailscale/k8s-operator"
          tag  = "v1.84.0"
        }
        hostname = "${local.name}-k8s-operator"
      }
      apiServerProxyConfig = {
        mode = "true"
        tags = "tag:k8s-operator,tag:k8s-api-server"
      }
      oauth = {
        clientId     = local.tailscale_oauth_client_id
        clientSecret = local.tailscale_oauth_client_secret
        hostname     = "${local.name}-operator"
        tags         = "tag:k8s-operator"
      }
    })
  ]

  set_sensitive {
    name  = "oauth.clientId"
    value = local.tailscale_oauth_client_id
  }

  set_sensitive {
    name  = "oauth.clientSecret"
    value = local.tailscale_oauth_client_secret
  }

  depends_on = [
    kubernetes_namespace.tailscale_operator,
    aws_eks_node_group.main,
  ]
}

# Security group for EKS cluster
resource "aws_security_group" "cluster" {
  name_prefix = "${local.name}-cluster-"
  vpc_id      = data.aws_vpc.default.id

  tags = merge(
    local.aws_tags,
    {
      Name = "${local.name}-cluster"
    }
  )
}

resource "aws_security_group_rule" "cluster_egress" {
  security_group_id = aws_security_group.cluster.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
}

# Security group for DERP nodes with all required ports
resource "aws_security_group" "derp_nodes" {
  vpc_id = data.aws_vpc.default.id
  name   = "${local.name}-derp-nodes"

  tags = merge(
    local.aws_tags,
    {
      Name = "${local.name}-derp-nodes"
    }
  )
}

# ICMP (ping) traffic
resource "aws_security_group_rule" "derp_icmp_ingress" {
  security_group_id = aws_security_group.derp_nodes.id
  type              = "ingress"
  from_port         = -1
  to_port           = -1
  protocol          = "icmp"
  cidr_blocks       = ["0.0.0.0/0"]
}

# SSH access
resource "aws_security_group_rule" "derp_ssh_ingress" {
  security_group_id = aws_security_group.derp_nodes.id
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

# DERP HTTP
resource "aws_security_group_rule" "derp_http_ingress" {
  security_group_id = aws_security_group.derp_nodes.id
  type              = "ingress"
  from_port         = var.derp_http_port
  to_port           = var.derp_http_port
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

# DERP HTTPS
resource "aws_security_group_rule" "derp_https_ingress" {
  security_group_id = aws_security_group.derp_nodes.id
  type              = "ingress"
  from_port         = var.derp_https_port
  to_port           = var.derp_https_port
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

# DERP STUN TCP
resource "aws_security_group_rule" "derp_stun_tcp_ingress" {
  security_group_id = aws_security_group.derp_nodes.id
  type              = "ingress"
  from_port         = var.derp_stun_port
  to_port           = var.derp_stun_port
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

# DERP STUN UDP
resource "aws_security_group_rule" "derp_stun_udp_ingress" {
  security_group_id = aws_security_group.derp_nodes.id
  type              = "ingress"
  from_port         = var.derp_stun_port
  to_port           = var.derp_stun_port
  protocol          = "udp"
  cidr_blocks       = ["0.0.0.0/0"]
}

# Tailscale specific port
resource "aws_security_group_rule" "tailscale_ingress" {
  security_group_id = aws_security_group.derp_nodes.id
  type              = "ingress"
  from_port         = 41641
  to_port           = 41641
  protocol          = "udp"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
}

# All egress traffic
resource "aws_security_group_rule" "derp_egress" {
  security_group_id = aws_security_group.derp_nodes.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
}

# Internal VPC traffic
resource "aws_security_group_rule" "internal_vpc_ingress" {
  security_group_id = aws_security_group.derp_nodes.id
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = [data.aws_vpc.default.cidr_block]
}

# IAM Role for EKS Cluster
resource "aws_iam_role" "cluster" {
  name = "${local.name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = local.aws_tags
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

# IAM Role for EKS Node Group
resource "aws_iam_role" "node_group" {
  name = "${local.name}-node-group-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = local.aws_tags
}

resource "aws_iam_role_policy_attachment" "node_group_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_group.name
}

resource "aws_iam_role_policy_attachment" "node_group_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_group.name
}

resource "aws_iam_role_policy_attachment" "node_group_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_group.name
} 