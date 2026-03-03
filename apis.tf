# ------------------------------------------------------------------------------
# APIs necesarias para que funcione esta infraestructura de control
# (presupuesto, Pub/Sub, Cloud Run para la función, Service Usage para deshabilitar)
# ------------------------------------------------------------------------------

locals {
  control_apis = [
    "billingbudgets.googleapis.com",
    "pubsub.googleapis.com",
    "run.googleapis.com",
    "serviceusage.googleapis.com",
    "storage.googleapis.com",
    "eventarc.googleapis.com",
    "cloudbuild.googleapis.com"
  ]
}

resource "google_project_service" "control_apis" {
  for_each = toset(local.control_apis)

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}
