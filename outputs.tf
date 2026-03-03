# ------------------------------------------------------------------------------
# Salidas de la infraestructura de control
# ------------------------------------------------------------------------------

output "project_id" {
  description = "Proyecto GCP donde está desplegado el control."
  value       = var.project_id
}

output "budget_notifications_topic" {
  description = "Topic de Pub/Sub al que Billing envía las alertas de presupuesto."
  value       = google_pubsub_topic.budget_notifications.id
}

output "budget_guard_function" {
  description = "Nombre de la Cloud Function que deshabilita APIs al superar presupuesto."
  value       = google_cloudfunctions2_function.budget_guard.name
}

output "apis_controlled_on_budget_exceeded" {
  description = "Lista de APIs que se deshabilitan cuando se supera el presupuesto (fácil de ampliar)."
  value       = var.apis_to_control_on_budget_exceeded
}
