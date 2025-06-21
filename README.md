# Tailscale Kubernetes Custom DERP Server

A production-ready AWS EKS deployment for running custom Tailscale DERP (Detour Encrypted Relay Proxy) servers with comprehensive monitoring, automated certificate management, and dual-stack IPv4/IPv6 networking.

## Architecture Overview

This project deploys a highly available Tailscale DERP infrastructure on AWS EKS featuring:

- **Dual-Stack EKS Cluster** - IPv4/IPv6 networking on ARM-based nodes
- **Custom DERP Servers** - DaemonSet deployment with host networking
- **Automated TLS** - Let's Encrypt certificates via cert-manager
- **Dynamic DNS** - Cloudflare API integration for hostname resolution
- **Comprehensive Monitoring** - Prometheus, Grafana, and custom DERP metrics
- **Infrastructure as Code** - Terraform for AWS resources, Kustomize for K8s manifests

## Quick Start

### Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.0
- kubectl
- Make
- Tailscale account with OAuth credentials
- Cloudflare account with API token
- Domain name managed by Cloudflare

### 1. Clone and Configure

```bash
git clone https://github.com/rajsinghtech/ts-k8s-customderp.git
cd ts-k8s-customderp
```

### 2. Set Environment Variables

Create `infra/terraform/terraform.tfvars`:

```hcl
region       = "us-east-1"
cluster_name = "your-derp-cluster"
instance_type = "c6g.xlarge"

# Tailscale OAuth credentials
tailscale_oauth_client_id     = "your-client-id"
tailscale_oauth_client_secret = "your-client-secret"

# DERP server ports
derp_http_port  = 80
derp_https_port = 443
derp_stun_port  = 3478
```

### 3. Deploy Infrastructure

```bash
make start
```

This command will:
1. Deploy EKS cluster with Terraform
2. Install cert-manager and Tailscale operator
3. Deploy DERP servers and monitoring stack

## Project Structure

```
├── infra/
│   └── terraform/          # AWS EKS infrastructure
│       ├── main.tf          # EKS cluster, VPC, security groups
│       ├── variables.tf     # Configuration variables
│       └── outputs.tf       # Cluster outputs
├── kustomize/
│   ├── derp/               # DERP server manifests
│   │   ├── daemonset.yaml  # DERP server deployment
│   │   ├── ddns.yaml       # Dynamic DNS updater
│   │   └── issuer.yaml     # Let's Encrypt certificate issuer
│   └── monitoring/         # Prometheus stack
│       ├── values.yaml     # Monitoring configuration
│       └── dashboards/     # Grafana dashboards
└── Makefile               # Automation commands
```

## Components

### EKS Cluster

- **Version**: Kubernetes 1.33
- **Nodes**: ARM-based c6g.xlarge instances (2 desired, 1-2 range)
- **Networking**: Dual-stack IPv4/IPv6 with custom VPC
- **Addons**: CoreDNS, kube-proxy, VPC-CNI, EBS CSI driver

### DERP Server

- **Image**: `ghcr.io/erisa/ts-derper:latest` ([Erisa's excellent work](https://github.com/Erisa/ts-derp-docker))
- **Deployment**: DaemonSet with host networking for reduced NAT exposure
- **Ports**: HTTP (80), HTTPS (443), STUN (3478)
- **Certificate**: Automated Let's Encrypt via DNS-01 challenge
- **DNS**: Dynamic hostname mapping via Cloudflare API

### Monitoring

- **Prometheus Stack**: Full monitoring with 30-day retention
- **Grafana Dashboards**: Tailscale and DERP-specific metrics
- **DERP Probe**: Custom probe with Prometheus metrics ([custom build](https://github.com/users/rajsinghtech/packages/container/package/derpprobe))
- **Alerts**: Connection health and performance monitoring

### Security

- **Network Policies**: Comprehensive security groups for all protocols
- **TLS Everywhere**: Automated certificate management
- **Least Privilege**: Minimal IAM permissions and RBAC
- **Encryption**: EBS volumes encrypted at rest

## Make Commands

```bash
# Deploy full infrastructure
make start

# Plan Terraform changes
make plan

# Apply Terraform changes
make apply

# Deploy Kubernetes manifests
make apply-manifests

# Check cluster status
make status

# Clean up
make clean
```

## Network Configuration

### Security Groups

The cluster includes security group rules for both IPv4 and IPv6:

- **DERP Traffic**: HTTP/HTTPS (80/443), STUN (3478)
- **Management**: SSH (22), ICMP ping
- **Tailscale**: UDP 41641
- **Internal**: Full VPC communication

### DNS and Certificates

- **Domain Pattern**: `{node-name}.derp.rajsingh.info`
- **Certificate**: Wildcard cert `*.ec2.internal.derp.rajsingh.info`
- **Challenge**: DNS-01 via Cloudflare API
- **DDNS**: Automatic A/AAAA record updates

## Monitoring and Observability

### Dashboards

Access monitoring via Tailscale ingress:

- **Grafana**: Tailscale and DERP dashboards
- **Prometheus**: Metrics and alerting
- **DERP Probe**: Region health and latency metrics

### Key Metrics

- Connection efficiency and dropped packets
- DERP probe latency and failures
- Node resource utilization
- Certificate expiration tracking

## Security Considerations

- All communication encrypted with Tailscale
- EBS volumes encrypted at rest
- Least privilege IAM roles
- Network policies restricting traffic
- Automated security updates

## Acknowledgments

- [Erisa](https://github.com/Erisa) for the excellent [ts-derp-docker](https://github.com/Erisa/ts-derp-docker) implementation
- Tailscale team for the DERP protocol and tooling
- AWS EKS and Kubernetes communities

---

**Note**: This is a production-focused deployment. Ensure you understand the costs and security implications before deploying to AWS.