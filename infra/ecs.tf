resource "aws_ecs_cluster" "this" {
  name = "${var.project_name}-cluster"
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 14
}

# The container image tag below is a placeholder. Each run of the GitHub
# Actions CD workflow registers a new task definition revision pointing at the
# real image and updates the service to use it. Kept when the app is switched
# off, so its revisions (and the last deployed image) survive.
resource "aws_ecs_task_definition" "this" {
  family                   = "${var.project_name}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = "app"
      image     = "${aws_ecr_repository.this.repository_url}:placeholder"
      essential = true
      portMappings = [{
        containerPort = var.container_port
        protocol      = "tcp"
      }]
      environment = [
        { name = "ALLOWED_HOSTS", value = local.app_fqdn }
      ]
      secrets = [
        {
          name      = "SECRET_KEY_BASE"
          valueFrom = aws_ssm_parameter.secret_key_base.arn
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "app"
        }
      }
    }
  ])

  lifecycle {
    ignore_changes = [container_definitions]
  }
}

# The newest revision in the family: the one the CD workflow deployed last.
# When the app is switched back on, the recreated service starts on that
# revision (the last deployed image), not Terraform's placeholder.
# depends_on makes Terraform read this after the task definition exists.
data "aws_ecs_task_definition" "latest" {
  task_definition = aws_ecs_task_definition.this.family
  depends_on      = [aws_ecs_task_definition.this]
}

resource "aws_ecs_service" "this" {
  count = local.enabled

  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = data.aws_ecs_task_definition.latest.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.selected.ids
    security_groups  = [aws_security_group.service.id]
    assign_public_ip = true # no NAT gateway; outbound is limited to HTTPS by the security group
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this[0].arn
    container_name   = "app"
    container_port   = var.container_port
  }

  depends_on = [aws_lb_listener.https]

  lifecycle {
    # The CD workflow owns which revision runs after creation.
    ignore_changes = [task_definition, desired_count]
  }
}
