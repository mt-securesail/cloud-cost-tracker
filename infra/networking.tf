# Uses the account's default VPC to keep this simple and cheap (no NAT gateway).
# A production setup would use a purpose-built VPC with private subnets.

data "aws_vpc" "default" {
  default = true
}

# The default subnet in each of the two chosen AZs.
data "aws_subnets" "selected" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
  filter {
    name   = "availability-zone"
    values = var.availability_zones
  }
}

# The security groups stay even when the app is switched off: they cost
# nothing, and the ZAP scan role's permissions point at the ALB group.
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Allow inbound HTTPS (and HTTP, redirected) to the ALB from allowed IPs"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTPS from allowed IPs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  # Port 80 only redirects to HTTPS (alb.tf); it never serves the app.
  ingress {
    description = "HTTP from allowed IPs (redirect to HTTPS only)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }

  # The ALB only needs to reach the app containers (and health-check them) on
  # the container port inside this VPC. (Pointing at the service security
  # group instead would create a circular reference between the two groups.)
  egress {
    description = "To app containers in this VPC"
    from_port   = var.container_port
    to_port     = var.container_port
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }
}

resource "aws_security_group" "service" {
  name        = "${var.project_name}-service-sg"
  description = "Allow inbound traffic from the ALB only"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "From the ALB"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  # Outbound HTTPS only. The task needs it to pull its image (ECR), send logs
  # (CloudWatch), read SECRET_KEY_BASE (SSM), and call Cost Explorer/CloudWatch.
  # Exception: Trivy flags any 0.0.0.0/0 egress (AWS-0104). Removing it needs
  # VPC endpoints (~$7+/month each), declined to keep this app cheap.
  # Decided by the repo owner (mt-securesail), 2026-11-13. Review by 2027-01-31.
  #trivy:ignore:AWS-0104:exp:2027-01-31
  egress {
    description = "Outbound HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
