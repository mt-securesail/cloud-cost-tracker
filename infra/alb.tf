# Everything in this file exists only while the app is switched on
# (count = local.enabled; see app_enabled in variables.tf).

# Exception: Trivy flags a public ALB (AWS-0053). It's public by design; access
# is limited to allowed_cidrs by its security group. Decided by the repo owner
# (mt-securesail), 2026-11-13. Revisit if Cognito login (PRD L2) replaces the IP allow-list.
#trivy:ignore:AWS-0053
resource "aws_lb" "this" {
  count = local.enabled

  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.selected.ids # exactly two (variables.tf)

  # Reject requests with malformed headers (request-smuggling defense; Trivy AWS-0052).
  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "this" {
  count = local.enabled

  name        = "${var.project_name}-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  # How long a departing container keeps receiving in-flight requests before
  # it's removed. AWS's default is 300 s; this app's requests take well under
  # a second, so 30 s is plenty. It shortens every deploy and the app_enabled
  # switch-off (which took ~8 min at 300 s).
  deregistration_delay = 30

  health_check {
    path                = "/up"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    interval            = 30
    timeout             = 10
  }
}

# HTTPS: TLS 1.2 and 1.3 only, with the ACM certificate from dns.tf.
resource "aws_lb_listener" "https" {
  count = local.enabled

  load_balancer_arn = aws_lb.this[0].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.this.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[0].arn
  }
}

# HTTP only redirects to HTTPS. It never forwards to the app.
resource "aws_lb_listener" "http_redirect" {
  count = local.enabled

  load_balancer_arn = aws_lb.this[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}
