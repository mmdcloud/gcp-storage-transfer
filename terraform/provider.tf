terraform {
  required_version = "~> 1.11.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.11.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.40"
    }
  }
}

provider "google" {
  project = var.project_id
}

provider "random" {}

provider "aws" {
  region = "us-east-1"
}

provider "azurerm" {
  features {}
}

provider "azuread" {}