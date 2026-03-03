# ------------------------------------------------------------------------------
# Cloud Function que deshabilita las APIs configuradas cuando se supera el presupuesto.
# ------------------------------------------------------------------------------

data "archive_file" "budget_guard_zip" {
  type        = "zip"
  source_dir  = "${path.module}/functions/budget_guard"
  output_path = "${path.module}/budget_guard.zip"
}

resource "google_storage_bucket" "function_source" {
  name     = "${var.project_id}-finops-control-${data.google_project.current.number}"
  project  = var.project_id
  location = var.region

  uniform_bucket_level_access = true
  force_destroy               = true

  depends_on = [google_project_service.control_apis]
}

resource "google_storage_bucket_object" "budget_guard_zip" {
  name   = "budget_guard-${data.archive_file.budget_guard_zip.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.budget_guard_zip.output_path
}

resource "google_service_account" "budget_guard" {
  account_id   = "finops-budget-guard"
  display_name = "FinOps Budget Guard - Deshabilita APIs al superar presupuesto"
  project      = var.project_id
}

# Permiso para deshabilitar APIs en el proyecto (Service Usage)
resource "google_project_iam_member" "budget_guard_service_usage" {
  project = var.project_id
  role    = "roles/serviceusage.serviceUsageAdmin"
  member  = "serviceAccount:${google_service_account.budget_guard.email}"
}

resource "google_cloudfunctions2_function" "budget_guard" {
  name     = "budget-guard"
  location = var.region
  project  = var.project_id

  build_config {
    runtime     = "python312"
    entry_point = "budget_guard"
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.budget_guard_zip.name
      }
    }
  }

  service_config {
    max_instance_count = 1
    available_memory   = "256Mi"
    timeout_seconds    = 120
    service_account_email = google_service_account.budget_guard.email

    environment_variables = {
      GCP_PROJECT             = var.project_id
      APIS_TO_DISABLE_ON_BUDGET = jsonencode(var.apis_to_control_on_budget_exceeded)
    }
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.budget_notifications.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }

  depends_on = [
    google_project_service.control_apis,
    google_storage_bucket_object.budget_guard_zip,
    google_pubsub_topic.budget_notifications,
    google_project_iam_member.budget_guard_service_usage
  ]
}
