.PHONY: help init validate plan apply destroy clean lint format test deploy-dev deploy-staging deploy-prod

# Default target
help: ## Show this help message
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# Terraform basic operations
init: ## Initialize Terraform working directory
	@echo "Initializing Terraform..."
	cd terraform && terraform init

validate: ## Validate Terraform configuration
	@echo "Validating Terraform configuration..."
	cd terraform && terraform validate

plan: ## Show Terraform execution plan
	@echo "Generating Terraform plan..."
	cd terraform && terraform plan

apply: ## Apply Terraform configuration
	@echo "Applying Terraform configuration..."
	cd terraform && terraform apply

destroy: ## Destroy Terraform-managed infrastructure
	@echo "Destroying Terraform-managed infrastructure..."
	cd terraform && terraform destroy

# Environment-specific targets
deploy-dev: ## Deploy to development environment
	@echo "Deploying to development environment..."
	cd terraform && terraform workspace select dev || terraform workspace new dev
	cd terraform && terraform apply -var-file=environments/dev/terraform.tfvars

deploy-staging: ## Deploy to staging environment
	@echo "Deploying to staging environment..."
	cd terraform && terraform workspace select staging || terraform workspace new staging
	cd terraform && terraform apply -var-file=environments/staging/terraform.tfvars

deploy-prod: ## Deploy to production environment
	@echo "Deploying to production environment..."
	cd terraform && terraform workspace select prod || terraform workspace new prod
	cd terraform && terraform apply -var-file=environments/prod/terraform.tfvars

# Plan for specific environments
plan-dev: ## Show plan for development environment
	@echo "Generating plan for development environment..."
	cd terraform && terraform workspace select dev || terraform workspace new dev
	cd terraform && terraform plan -var-file=environments/dev/terraform.tfvars

plan-staging: ## Show plan for staging environment
	@echo "Generating plan for staging environment..."
	cd terraform && terraform workspace select staging || terraform workspace new staging
	cd terraform && terraform plan -var-file=environments/staging/terraform.tfvars

plan-prod: ## Show plan for production environment
	@echo "Generating plan for production environment..."
	cd terraform && terraform workspace select prod || terraform workspace new prod
	cd terraform && terraform plan -var-file=environments/prod/terraform.tfvars

# Destroy for specific environments
destroy-dev: ## Destroy development environment
	@echo "Destroying development environment..."
	cd terraform && terraform workspace select dev
	cd terraform && terraform destroy -var-file=environments/dev/terraform.tfvars

destroy-staging: ## Destroy staging environment
	@echo "Destroying staging environment..."
	cd terraform && terraform workspace select staging
	cd terraform && terraform destroy -var-file=environments/staging/terraform.tfvars

destroy-prod: ## Destroy production environment
	@echo "Destroying production environment..."
	cd terraform && terraform workspace select prod
	cd terraform && terraform destroy -var-file=environments/prod/terraform.tfvars

# Utility targets
clean: ## Clean temporary files and artifacts
	@echo "Cleaning temporary files..."
	rm -rf terraform/tmp/*
	rm -rf terraform/.terraform/
	rm -f terraform/.terraform.lock.hcl
	rm -f terraform/terraform.tfstate*
	rm -f terraform/terraform.tfstate.backup

lint: ## Lint Terraform configuration
	@echo "Linting Terraform configuration..."
	cd terraform && terraform fmt -check -diff
	cd terraform && terraform validate

format: ## Format Terraform configuration
	@echo "Formatting Terraform configuration..."
	cd terraform && terraform fmt

test: ## Run Terraform tests
	@echo "Running Terraform tests..."
	cd terraform && terraform test

# Lambda packaging
package-lambda: ## Package Lambda functions
	@echo "Packaging Lambda functions..."
	mkdir -p terraform/tmp
	cd src/ingest_worker && zip -r ../../terraform/tmp/ingest_lambda.zip .
	cd src/query_api && zip -r ../../terraform/tmp/query_lambda.zip .

# State management
state-list: ## List Terraform workspaces
	@echo "Listing Terraform workspaces..."
	cd terraform && terraform workspace list

state-show: ## Show current Terraform state
	@echo "Showing current Terraform state..."
	cd terraform && terraform show

# Import operations (for existing infrastructure)
import-s3: ## Import existing S3 buckets (requires BUCKET_NAME env var)
	@if [ -z "$(BUCKET_NAME)" ]; then echo "Error: BUCKET_NAME environment variable is required"; exit 1; fi
	@echo "Importing S3 bucket: $(BUCKET_NAME)"
	cd terraform && terraform import aws_s3_bucket.raw_files $(BUCKET_NAME)

# Backup and restore
backup-state: ## Backup Terraform state
	@echo "Backing up Terraform state..."
	cd terraform && cp terraform.tfstate terraform.tfstate.backup.$(shell date +%Y%m%d-%H%M%S)

restore-state: ## Restore Terraform state (requires BACKUP_FILE env var)
	@if [ -z "$(BACKUP_FILE)" ]; then echo "Error: BACKUP_FILE environment variable is required"; exit 1; fi
	@echo "Restoring Terraform state from: $(BACKUP_FILE)"
	cd terraform && cp $(BACKUP_FILE) terraform.tfstate

# Documentation
docs-generate: ## Generate Terraform documentation
	@echo "Generating Terraform documentation..."
	cd terraform && terraform graph | dot -Tpng > infrastructure-diagram.png

# Security and compliance
security-scan: ## Run security scan on Terraform configuration
	@echo "Running security scan..."
	@if command -v tfsec >/dev/null 2>&1; then \
		cd terraform && tfsec .; \
	else \
		echo "tfsec not found. Install with: brew install tfsec"; \
	fi

# Cost estimation
cost-estimate: ## Estimate infrastructure costs
	@echo "Estimating infrastructure costs..."
	@if command -v infracost >/dev/null 2>&1; then \
		cd terraform && infracost breakdown; \
	else \
		echo "infracost not found. Install with: curl -fsSL https://raw.githubusercontent.com/infracost/infracost/master/scripts/install.sh | sh"; \
	fi

# Quick deploy commands for development
quick-deploy: package-lambda apply ## Quick deploy for development (package and apply)

dev-setup: init plan-dev ## Setup development environment (init and plan)

# CI/CD helpers
ci-validate: lint validate ## CI: lint and validate configuration

ci-plan: init plan-dev ## CI: initialize and plan for dev

# Custom environment deployment
deploy-custom: ## Deploy to custom environment (requires ENV env var)
	@if [ -z "$(ENV)" ]; then echo "Error: ENV environment variable is required"; exit 1; fi
	@echo "Deploying to custom environment: $(ENV)"
	cd terraform && terraform workspace select $(ENV) || terraform workspace new $(ENV)
	cd terraform && terraform apply -var-file=environments/$(ENV)/terraform.tfvars