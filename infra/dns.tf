# --- Domain, certificate, and DNS record ---
# The hosted zone was created by Route 53 when the domain was registered.
# Terraform only looks it up (never creates or deletes it), so other projects
# can add their own subdomains to the same domain.
data "aws_route53_zone" "this" {
  name         = var.domain_name
  private_zone = false
}

# Free public TLS certificate for the app's hostname, validated through DNS.
# Kept when the app is switched off (it costs nothing), so turning the app
# back on doesn't wait for a new certificate.
resource "aws_acm_certificate" "this" {
  domain_name       = local.app_fqdn
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for o in aws_acm_certificate.this.domain_validation_options : o.domain_name => {
      name   = o.resource_record_name
      type   = o.resource_record_type
      record = o.resource_record_value
    }
  }

  zone_id         = data.aws_route53_zone.this.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 300
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

# aws-cost-est.<domain> -> the load balancer. Removed with the ALB when the app
# is switched off, and recreated pointing at the new ALB when it's back on, so
# the URL never changes.
resource "aws_route53_record" "app" {
  count = local.enabled

  zone_id = data.aws_route53_zone.this.zone_id
  name    = local.app_fqdn
  type    = "A"

  alias {
    name                   = aws_lb.this[0].dns_name
    zone_id                = aws_lb.this[0].zone_id
    evaluate_target_health = true
  }
}
