output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane"
  value       = aws_security_group.cluster.id
}

output "cluster_name" {
  description = "Kubernetes Cluster Name"
  value       = aws_eks_cluster.main.name
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "derp_nodes_security_group_id" {
  description = "Security group ID for EKS nodes with DERP and ICMP access"
  value       = aws_security_group.derp_nodes.id
}

output "cluster_version" {
  description = "The Kubernetes version for the cluster"
  value       = aws_eks_cluster.main.version
}

output "cluster_arn" {
  description = "The Amazon Resource Name (ARN) of the cluster"
  value       = aws_eks_cluster.main.arn
}

output "node_group_arn" {
  description = "EKS node group ARN"
  value       = aws_eks_node_group.main.arn
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