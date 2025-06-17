output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane"
  value       = module.eks.cluster_primary_security_group_id
}

output "cluster_name" {
  description = "Kubernetes Cluster Name"
  value       = module.eks.cluster_name
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = module.eks.cluster_certificate_authority_data
}

output "node_security_group_id" {
  description = "Security group ID for EKS nodes"
  value       = module.eks.node_security_group_id
}

output "cluster_version" {
  description = "The Kubernetes version for the cluster"
  value       = module.eks.cluster_version
}

output "cluster_arn" {
  description = "The Amazon Resource Name (ARN) of the cluster"
  value       = module.eks.cluster_arn
}

output "node_group_arn" {
  description = "EKS node group ARN"
  value       = [for ng in module.eks.eks_managed_node_groups : ng.node_group_arn][0]
}

output "vpc_id" {
  description = "ID of the VPC where the cluster is deployed"
  value       = data.aws_vpc.default.id
}

output "subnet_ids" {
  description = "List of subnet IDs where the cluster is deployed"
  value       = data.aws_subnets.default.ids
}

output "tailscale_operator_namespace" {
  description = "Kubernetes namespace where Tailscale operator is deployed"
  value       = kubernetes_namespace.tailscale_operator.metadata[0].name
}

output "cert_manager_namespace" {
  description = "Kubernetes namespace where cert-manager is deployed"
  value       = kubernetes_namespace.cert_manager.metadata[0].name
}

output "subnet_public_ip_assignment" {
  description = "Shows which subnets have public IP auto-assignment enabled"
  value = {
    for subnet_id, subnet in data.aws_subnet.default_subnets : 
    subnet_id => {
      availability_zone = subnet.availability_zone
      map_public_ip_on_launch = subnet.map_public_ip_on_launch
      cidr_block = subnet.cidr_block
    }
  }
} 