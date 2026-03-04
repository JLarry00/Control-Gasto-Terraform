# ------------------------------------------------------------------------------
# Topic para notificaciones de presupuesto; Billing publicará aquí las alertas.
# ------------------------------------------------------------------------------

resource "google_pubsub_topic" "budget_notifications" {
  name    = "budget-notifications"
  project = var.project_id

  depends_on = [google_project_service.control_apis]
}

# La cuenta de servicio de Cloud Billing debe poder publicar en el topic.
# Ver: https://cloud.google.com/billing/docs/how-to/budgets-programmatic-notifications
# resource "google_pubsub_topic_iam_member" "billing_publisher" {
#   project = var.project_id
#   topic   = google_pubsub_topic.budget_notifications.name
#   role    = "roles/pubsub.publisher"
#   member  = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-billing.iam.gserviceaccount.com"

#   depends_on = [
#     google_billing_budget.per_api
#   ]
# }
