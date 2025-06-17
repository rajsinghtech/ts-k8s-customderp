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

################################################################################
# Data sources and Provider Initialization                                     #
################################################################################

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

################################################################################
# EKS Cluster                                                                  #
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.name
  cluster_version = local.cluster_version
  
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]
  
  enable_cluster_creator_admin_permissions = true
  enable_irsa = true
  
  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
  }

  # Enable logging
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cloudwatch_log_group_retention_in_days = 7

  vpc_id     = data.aws_vpc.default.id
  subnet_ids = data.aws_subnets.default.ids

  eks_managed_node_groups = {
    "${local.name}-nodes" = {
      instance_types = [local.node_instance_type]
      capacity_type  = local.node_capacity_type
      ami_type       = local.node_ami_type

      min_size     = local.min_size
      max_size     = local.max_size
      desired_size = local.desired_size

      # Enable public IP assignment for nodes
      associate_public_ip_address = true

      # SSH key configuration
      key_name = var.key_name

      update_config = {
        max_unavailable = 1
      }

      tags = merge(
        local.aws_tags,
        {
          Name = "${local.name}-eks-node"
        }
      )
    }
  }

  # Additional security group rules for DERP and ICMP
  node_security_group_additional_rules = {
    # ICMP (ping) traffic
    ingress_icmp = {
      description = "ICMP ping traffic"
      protocol    = "icmp"
      from_port   = -1
      to_port     = -1
      type        = "ingress"
      cidr_blocks = ["0.0.0.0/0"]
    }

    # SSH access
    ingress_ssh = {
      description = "SSH access"
      protocol    = "tcp"
      from_port   = 22
      to_port     = 22
      type        = "ingress"
      cidr_blocks = ["0.0.0.0/0"]
    }

    # DERP HTTP
    ingress_derp_http = {
      description = "DERP HTTP traffic"
      protocol    = "tcp"
      from_port   = var.derp_http_port
      to_port     = var.derp_http_port
      type        = "ingress"
      cidr_blocks = ["0.0.0.0/0"]
    }

    # DERP HTTPS
    ingress_derp_https = {
      description = "DERP HTTPS traffic"
      protocol    = "tcp"
      from_port   = var.derp_https_port
      to_port     = var.derp_https_port
      type        = "ingress"
      cidr_blocks = ["0.0.0.0/0"]
    }

    # DERP STUN TCP
    ingress_derp_stun_tcp = {
      description = "DERP STUN TCP traffic"
      protocol    = "tcp"
      from_port   = var.derp_stun_port
      to_port     = var.derp_stun_port
      type        = "ingress"
      cidr_blocks = ["0.0.0.0/0"]
    }

    # DERP STUN UDP
    ingress_derp_stun_udp = {
      description = "DERP STUN UDP traffic"
      protocol    = "udp"
      from_port   = var.derp_stun_port
      to_port     = var.derp_stun_port
      type        = "ingress"
      cidr_blocks = ["0.0.0.0/0"]
    }

    # Tailscale specific port
    ingress_tailscale = {
      description      = "Tailscale UDP traffic"
      protocol         = "udp"
      from_port        = 41641
      to_port          = 41641
      type             = "ingress"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
    }

    # Allow all traffic within the VPC
    ingress_vpc_all = {
      description = "Allow all traffic within VPC"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      protocol    = "-1"
      cidr_blocks = [data.aws_vpc.default.cidr_block]
    }

    # Allow all traffic within the worker-node security group
    ingress_self_all = {
      description = "Allow all traffic within the worker-node security group"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      protocol    = "-1"
      self        = true
    }
  }

  tags = local.aws_tags
}

################################################################################
# Kubernetes Resources                                                         #
################################################################################

# Kubernetes namespace for Tailscale operator
resource "kubernetes_namespace" "tailscale_operator" {
  metadata {
    name = "tailscale"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }

  depends_on = [module.eks]
}

# Kubernetes namespace for DERP server
resource "kubernetes_namespace" "derp" {
  metadata {
    name = "derp"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }

  depends_on = [module.eks]
}

# Kubernetes namespace for cert-manager
resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = "cert-manager"
  }

  depends_on = [module.eks]
}

# Deploy cert-manager using Helm
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.18.0"
  namespace  = kubernetes_namespace.cert_manager.metadata[0].name

  values = [
    yamlencode({
      installCRDs = true
      dns01RecursiveNameserversOnly = true
      extraArgs = [
        "--dns01-recursive-nameservers=1.1.1.1:53,8.8.8.8:53",
        "--dns01-recursive-nameservers-only"
      ]
    })
  ]

  depends_on = [
    kubernetes_namespace.cert_manager,
    module.eks,
  ]
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
    module.eks,
  ]
} 