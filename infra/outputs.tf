# Values needed to set up GitHub (repo variables and secrets). See CLAUDE.md.
# Outputs about the switched-off parts are null while app_enabled = false.

output "app_url" {
  value = "https://${local.app_fqdn}"
}

output "alb_dns_name" {
  value = one(aws_lb.this[*].dns_name)
}

output "ecr_repository_name" {
  value = aws_ecr_repository.this.name
}

# Contains the AWS account ID: store it as a GitHub *secret*, not a variable,
# so it is masked in the public Actions logs.
output "github_deploy_role_arn" {
  value = aws_iam_role.github_deploy.arn
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.this.name
}

# The name, even while the service doesn't exist (the CD workflow checks for it).
output "ecs_service_name" {
  value = "${var.project_name}-service"
}

output "ecs_task_family" {
  value = aws_ecs_task_definition.this.family
}
