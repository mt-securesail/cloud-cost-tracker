variable "aws_region" {
  description = "AWS region to deploy into. Billing metrics and Cost Explorer live in us-east-1."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used to prefix all resources"
  type        = string
  default     = "cloud-cost-tracker"
}

variable "app_enabled" {
  description = "On/off switch. false removes the load balancer, ECS service, and DNS record (the costly parts) and keeps everything else, so turning it back on is one terraform apply."
  type        = bool
  default     = true
}

variable "domain_name" {
  description = "Domain registered in Route 53. Its hosted zone must already exist (Route 53 creates it at registration); Terraform only looks it up."
  type        = string
  default     = "example-apps.com"
}

variable "app_subdomain" {
  description = "The app is served at <app_subdomain>.<domain_name>"
  type        = string
  default     = "cloud-cost-est"
}

variable "availability_zones" {
  description = "Exactly two AZs for the load balancer and task. Two is the minimum an ALB allows; each public IPv4 address costs money."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "availability_zones must list exactly two AZs."
  }
}

variable "github_org" {
  description = "GitHub username or org that owns the repo"
  type        = string
}

variable "github_repo" {
  description = "GitHub repo name (without the org prefix)"
  type        = string
}

variable "github_oidc_sub_prefix" {
  description = "Optional. The OIDC subject prefix GitHub puts in tokens for this repo, e.g. repo:owner@123/repo@456. Get it with: gh api repos/OWNER/REPO/actions/oidc/customization/sub. If null, falls back to repo:<github_org>/<github_repo>."
  type        = string
  default     = null
}

variable "allowed_cidrs" {
  description = "IP ranges allowed to reach the load balancer, e.g. [\"203.0.113.7/32\"] for a single address. Use [\"0.0.0.0/0\"] only to open it to the whole internet."
  type        = list(string)

  validation {
    condition     = length(var.allowed_cidrs) > 0
    error_message = "allowed_cidrs must contain at least one CIDR range."
  }
}

variable "container_port" {
  description = "Port the Rails app listens on inside the container"
  type        = number
  default     = 3000
}

variable "secret_key_base" {
  description = "Rails secret_key_base. Generate locally with `openssl rand -hex 64`. Pass with -var, never commit this."
  type        = string
  sensitive   = true
}

locals {
  app_fqdn = "${var.app_subdomain}.${var.domain_name}"
  # 1 when the app is switched on, 0 when off. Used as `count` on the costly resources.
  enabled = var.app_enabled ? 1 : 0
}
