# Terraform EKS Cluster Management
TF_DIR = infra/terraform

start: init plan apply configure-kubectl
	@echo "Cluster deployment complete!"
	@echo "Run 'make status' to check cluster status"

stop: destroy-plan destroy
	@echo "Cluster destroyed!"

init:
	@echo "Initializing Terraform..."
	cd $(TF_DIR) && terraform init

plan:
	@echo "Planning Terraform deployment..."
	cd $(TF_DIR) && terraform plan

apply:
	@echo "Applying Terraform configuration..."
	cd $(TF_DIR) && terraform apply -auto-approve

destroy-plan:
	@echo "Planning Terraform destruction..."
	cd $(TF_DIR) && terraform plan -destroy

destroy:
	@echo "Destroying Terraform infrastructure..."
	cd $(TF_DIR) && terraform destroy -auto-approve

configure-kubectl:
	@echo "Configuring kubectl..."
	tailscale configure kubeconfig customderp-k8s-operator 

status:
	@echo "Cluster status:"
	kubectl get nodes -o wide
	@echo ""
	@echo "Security Group ID:"
	cd $(TF_DIR) && terraform output node_group_security_group_id

outputs:
	@echo "Terraform outputs:"
	cd $(TF_DIR) && terraform output

validate:
	@echo "Validating Terraform configuration..."
	cd $(TF_DIR) && terraform validate

format:
	@echo "Formatting Terraform files..."
	cd $(TF_DIR) && terraform fmt -recursive

clean:
	@echo "Cleaning Terraform state and cache..."
	cd $(TF_DIR) && rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup

test-ping:
	@echo "Testing ICMP connectivity to nodes..."
	@EXTERNAL_IP=$$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}'); \
	if [ -n "$$EXTERNAL_IP" ]; then \
		echo "Pinging node: $$EXTERNAL_IP"; \
		ping -c 3 $$EXTERNAL_IP; \
	else \
		echo "No external IP found for nodes"; \
	fi

apply-manifests:
	@echo "Applying manifests..."
	kustomize build kustomize/monitoring --enable-helm | kubectl apply --server-side -f - || true
	kustomize build kustomize/monitoring --enable-helm | kubectl apply --server-side -f - || true
	kubectl apply -k kustomize/derp

.PHONY: start stop init plan apply destroy-plan destroy configure-kubectl status outputs validate format clean test-ping