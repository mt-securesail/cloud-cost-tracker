data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.project_name}-ecs-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "execution_ssm" {
  statement {
    actions   = ["ssm:GetParameters"]
    resources = [aws_ssm_parameter.secret_key_base.arn]
  }

  # ECS decrypts SecureString parameters with the account's default SSM KMS
  # key (alias/aws/ssm). The execution role needs kms:Decrypt for that too.
  statement {
    actions   = ["kms:Decrypt"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.aws_region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "execution_ssm" {
  name   = "${var.project_name}-execution-ssm"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution_ssm.json
}

resource "aws_iam_role" "task" {
  name               = "${var.project_name}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

# What the running app may do in AWS: read billing data, nothing else (PRD 7.2).
# Cost Explorer and CloudWatch GetMetricData don't support resource-level
# permissions, so "*" is the only possible resource here; the actions are
# read-only. Cost Explorer calls cost $0.01 each, so the app's schedule (PRD 5)
# limits how often it calls them.
data "aws_iam_policy_document" "task_read_billing" {
  statement {
    sid = "ReadBillingData"
    actions = [
      "ce:GetCostAndUsage",
      "ce:GetCostForecast",
      "cloudwatch:GetMetricData",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "task_read_billing" {
  name   = "${var.project_name}-task-read-billing"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_read_billing.json
}

# --- GitHub Actions OIDC federation: lets Actions assume an AWS role without ---
# --- ever storing an AWS access key / secret key in GitHub. ---

# Newer GitHub repos put immutable numeric IDs in the OIDC "sub" claim
# (repo:owner@<id>/repo@<id>). Use the value GitHub reports for this repo
# when set; otherwise fall back to the name-based format.
locals {
  github_sub_prefix = coalesce(var.github_oidc_sub_prefix, "repo:${var.github_org}/${var.github_repo}")
}

# An AWS account can have only one OIDC provider for GitHub, and this account
# already has it (created by the rails-ecs-demo project's Terraform). Look it
# up instead of creating it. Never manage it here: destroying this project
# must not delete the other project's sign-in.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "github_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["${local.github_sub_prefix}:*"]
    }
  }
}

resource "aws_iam_role" "github_deploy" {
  name               = "${var.project_name}-github-deploy-role"
  assume_role_policy = data.aws_iam_policy_document.github_assume.json
}

data "aws_iam_policy_document" "github_deploy_permissions" {
  statement {
    sid       = "ECRAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "ECRPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
    ]
    resources = [aws_ecr_repository.this.arn]
  }

  statement {
    sid = "ECSDeploy"
    actions = [
      "ecs:DescribeTaskDefinition",
      "ecs:RegisterTaskDefinition",
      "ecs:DescribeServices",
      "ecs:UpdateService",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "PassRoles"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.execution.arn, aws_iam_role.task.arn]
  }
}

resource "aws_iam_role_policy" "github_deploy" {
  name   = "${var.project_name}-github-deploy-policy"
  role   = aws_iam_role.github_deploy.id
  policy = data.aws_iam_policy_document.github_deploy_permissions.json
}
