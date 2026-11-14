# Cloud Cost Tracker

A small, single-user dashboard that shows the current month's AWS charges, the forecast for the month, and where the
money is going by service. Built to stay open in a browser window while working on other AWS projects.

- Requirements: [`docs/PRD.md`](docs/PRD.md)
- Stack: Ruby 3.4, Rails 8.1, AWS ECS Fargate behind an ALB (HTTPS), Terraform in [`infra/`](infra/)
- Pipeline: GitHub Actions with tests, Brakeman, CodeQL, Dependency Review, Trivy, Grype, and OWASP ZAP
- Findings and accepted exceptions: [`docs/findings-log.md`](docs/findings-log.md)

AWS cost data is not real time: AWS updates it several times a day, so the dashboard shows when each number was last
updated.
