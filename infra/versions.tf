terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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
