terraform {
  # 1.11+ for write-only arguments (the Rails secret never enters the state file).
  required_version = ">= 1.11"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.100"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Every resource gets a Project tag, so this app's own running cost can be
  # filtered in Cost Explorer (once the tag is activated as a cost allocation tag).
  default_tags {
    tags = {
      Project = var.project_name
    }
  }
}
