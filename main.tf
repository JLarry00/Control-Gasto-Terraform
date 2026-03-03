# ------------------------------------------------------------------------------
# Infraestructura de control de presupuesto sobre APIs de Google Cloud
# Si una API se pasa de presupuesto, se apaga de forma automática.
# Código genérico: amplía apis_to_control_on_budget_exceeded para más APIs.
# ------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_project" "current" {
  project_id = var.project_id
}
