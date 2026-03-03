# ------------------------------------------------------------------------------
# Un presupuesto por API: cada uno solo cuenta el gasto de ese servicio.
# Cuando uno se supera, la notificación incluye budgetDisplayName = API id;
# la función deshabilita solo esa API.
# ------------------------------------------------------------------------------

resource "google_billing_budget" "per_api" {
  for_each = var.api_to_billing_service_id

  billing_account = var.billing_account_id
  # El display_name debe ser el API id para que la función sepa qué API deshabilitar
  display_name = each.key

  budget_filter {
    projects = ["projects/${data.google_project.current.number}"]
    services = ["services/${each.value}"]
  }

  amount {
    specified_amount {
      currency_code = var.budget_currency
      units         = tostring(var.budget_amount)
    }
  }

  dynamic "threshold_rules" {
    for_each = var.budget_alert_thresholds
    content {
      threshold_percent = threshold_rules.value
    }
  }

  all_updates_rule {
    pubsub_topic = google_pubsub_topic.budget_notifications.id
  }

  depends_on = [google_project_service.control_apis]
}
