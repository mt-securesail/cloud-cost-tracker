# Project context for Claude

AWS Cost Tracker: a single-user Rails dashboard showing the AWS account's current-month charges, forecast, and
by-service breakdown. Deployed to AWS ECS Fargate by GitHub Actions, with the same security pipeline as the
`mt-securesail/rails-ecs-demo` training repo. What to build is in `docs/PRD.md`; read it at the start of a session.

## How to talk to me

- Always say exactly where an instruction applies: the **AWS Management Console** (browser), the **GitHub website**,
  the **VS Code terminal**, or the **Claude Code panel**. Never just say "the console".
- Prefix PR and issue numbers with the repo name, e.g. "aws-cost-tracker/PR #3". I work on several repos at once.
- Be concise.

## Safety rules

- Never push to `main` or merge a PR without asking me first. Pushes to `main` deploy to production.
- Never run `terraform apply` or `terraform destroy` without showing me the plan and getting a clear yes.
- Do all experiments (including deliberately vulnerable code) on a new branch, and never merge them.
- Never put real secrets, keys, or tokens in files, commits, or prompts. Use clearly fake random values for
  secret-scanning tests. This repo is **public**.
- Never commit personal data: no real names, email addresses, IP addresses, or AWS account IDs. Use the GitHub
  username, placeholders, gitignored files (`infra/terraform.tfvars`), or GitHub secrets/variables instead. Check
  every diff for these before committing.
- This repo's GitHub Actions logs are public too. Keep role ARNs in GitHub **secrets** and `mask-aws-account-id: true`
  on every AWS credentials step.
- Warn me before any command that discards uncommitted work (for example `git reset --hard`).
- Cost Explorer API calls cost $0.01 each. Don't call `aws ce ...` without saying so first.

## Facts about this setup

- GitHub repo: `mt-securesail/aws-cost-tracker` (public). Default branch: `main`.
- App URL: `https://aws-cost-est.example-apps.com`. Domain registered in Route 53; Terraform only looks up its
  hosted zone.
- AWS region: `us-east-1`. Cluster `aws-cost-tracker-cluster`, service `aws-cost-tracker-service`.
- Infrastructure is Terraform in `infra/`, with state stored locally. `terraform.tfvars` and state files are
  gitignored.
- On/off switch: `app_enabled` in `infra/terraform.tfvars`. `false` removes the ALB, ECS service, and DNS record;
  the CD workflow then pushes the image but skips the deploy and production ZAP scan.
- GitHub OIDC: the account's one GitHub OIDC provider belongs to the rails-ecs-demo project. This project only looks
  it up (`data` source) and must never create or delete it. Trust policies use the repo's immutable subject prefix
  (`github_oidc_sub_prefix` in `terraform.tfvars`).
- Workflows: CI (`ci.yml`: tests, Brakeman), container scans (`container-scan.yml`: Trivy, Grype, Trivy config),
  `dependency-review.yml`, ZAP on PRs (`zap.yml`), and CD (`cd.yml`: CI, deploy via OIDC, then ZAP against
  production using the separate scan role in `infra/zap_scan.tf`).
- GitHub setup after `terraform apply` (values from `terraform output`):
  - Secrets: `AWS_DEPLOY_ROLE_ARN`, `AWS_ZAP_SCAN_ROLE_ARN`.
  - Variables: `AWS_REGION`, `ECR_REPOSITORY`, `ECS_CLUSTER`, `ECS_SERVICE`, `ECS_TASK_DEFINITION_FAMILY`,
    `CONTAINER_NAME` (`app`), `ALB_SECURITY_GROUP_ID`, `APP_URL`.
- Exceptions to scanner findings always carry a reason, the decider (`mt-securesail`), and a review date, and are
  logged in `docs/findings-log.md`.
