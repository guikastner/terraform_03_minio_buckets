terraform {
  required_version = ">= 1.6.0"

  required_providers {
    minio = {
      source  = "aminueza/minio"
      version = "~> 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}
