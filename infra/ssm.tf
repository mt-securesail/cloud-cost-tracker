# SSM reserves parameter names that start with "aws" or "ssm"
# (case-insensitive), so the secret sits under /apps/ to stay clear of that
# rule whatever project_name is.
resource "aws_ssm_parameter" "secret_key_base" {
  name  = "/apps/${var.project_name}/SECRET_KEY_BASE"
  type  = "SecureString"
  value = var.secret_key_base
}
