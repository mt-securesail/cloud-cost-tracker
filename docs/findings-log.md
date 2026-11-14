# Findings log

One row per finding: what was found, why, how it was fixed, and what now prevents it from coming back.
Sources include every scanner (Brakeman, CodeQL, Dependabot, Dependency Review, Trivy, Grype, ZAP), AI reviews, and
anything noticed by hand. Accepted exceptions are logged here too.

| # | Date | Finding | Source / severity | Root cause | Fix | Regression check | Link |
|---|---|---|---|---|---|---|---|
| 1 | 2026-11-13 | Starting point: ZAP rules 10038 (CSP), 10063 (Permissions Policy), 90004 (site isolation) set to `FAIL`; 10049 (non-storable content) `IGNORE` | Inherited from rails-ecs-demo (its findings #11-#14) | n/a: fixes copied in before the first scan | Security headers in `config/initializers/`, 404 page via `ErrorsController` | `test/security/security_headers_test.rb`, `.zap/rules.tsv` | cloud-cost-tracker/PR #1 |
| 2 | 2026-11-13 | Accepted: task egress to `0.0.0.0/0` on port 443 (Trivy AWS-0104) and public ALB (Trivy AWS-0053) | Trivy config; exceptions | No VPC endpoints (cost); ALB public by design, IP allow-listed | Inline `#trivy:ignore` with reason and review date in `infra/networking.tf`, `infra/alb.tf` | Exceptions expire or are reviewed by 2027-01-31 | cloud-cost-tracker/PR #1 |
| 3 | 2026-11-14 | Preventive: a commit could expose a personal email (author, committer, or `Co-authored-by`) in this public repo | Inherited from rails-ecs-demo; manual | GitHub's push-email block covers only the owner's own pushes, not co-author lines or other tools | `commit-privacy.yml` runs `.github/scripts/check-commit-emails.sh` on every PR; failing addresses are never printed | Required check `commit-emails` in the `protect-main` ruleset | cloud-cost-tracker/PR #1 |
