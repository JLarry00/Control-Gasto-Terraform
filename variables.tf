# ------------------------------------------------------------------------------
# Variables para la infraestructura de control de presupuesto
# ------------------------------------------------------------------------------

variable "project_id" {
  description = "ID del proyecto de Google Cloud donde está la infraestructura de servicios y donde se desplegará el control."
  type        = string
}

variable "billing_account_id" {
  description = "ID de la cuenta de facturación (ej. 012345-ABCDEF-678901) para crear el presupuesto y las alertas."
  type        = string
}

variable "region" {
  description = "Región por defecto para recursos (Cloud Run, etc.)."
  type        = string
  default     = "europe-west1"
}

variable "budget_amount" {
  description = "Importe máximo del presupuesto (en unidades, ej. 100 = 100 EUR/USD según currency_code)."
  type        = number
  default     = 1
}

variable "budget_currency" {
  description = "Código de moneda del presupuesto (ISO 4217)."
  type        = string
  default     = "EUR"
}

variable "budget_alert_thresholds" {
  description = "Umbrales de alerta del presupuesto (porcentaje 0-1, ej. 0.5 = 50%)."
  type        = list(number)
  default     = [1.0]
}

# ------------------------------------------------------------------------------
# Control por API: cada API tiene su propio presupuesto; al superarlo se
# deshabilita solo esa API. Mapa: API id (Service Usage) -> Billing service id.
# Los IDs de facturación se obtienen del Billing Catalog (consola o API).
# ------------------------------------------------------------------------------
variable "api_to_billing_service_id" {
  description = <<-EOT
    Mapa de API id (ej. run.googleapis.com) a ID de servicio de facturación (ej. 6F81-5844-456A).
    Se crea un presupuesto por entrada; cada presupuesto solo cuenta el gasto de ese servicio.
    Obtener IDs: Billing > Informes, o API https://cloud.google.com/billing/docs/how-tos/catalog-api
  EOT
  type        = map(string)
  # IDs de facturación: obtener en Billing > Informes o con Catalog API.
  # Formato por servicio: "XXXX-XXXX-XXXX". Sustituir por los de tu cuenta.
  default = {
    "run.googleapis.com"        = "E2C7-4E94-8B22"  # Cloud Run (ejemplo; verificar)
    "aiplatform.googleapis.com" = "2E3F-6D8A-1B4C"  # Vertex AI (verificar)
    "bigquery.googleapis.com"   = "24E6-581D-38E5"  # BigQuery (ejemplo doc GCP)
    "firebase.googleapis.com"   = "1A2B-3C4D-5E6F"  # Firebase (verificar)
    "container.googleapis.com"  = "6F81-5844-456A"  # GKE (verificar)
  }
}

# Lista de APIs que la función puede deshabilitar (solo si el presupuesto de esa API se supera).
variable "apis_to_control_on_budget_exceeded" {
  description = <<-EOT
    Lista de APIs (service IDs) que la función puede deshabilitar cuando su presupuesto se supere.
    Debe ser un subconjunto de las claves de api_to_billing_service_id.
  EOT
  type        = list(string)
  default = [
    "run.googleapis.com",
    "aiplatform.googleapis.com",
    "bigquery.googleapis.com",
    "firebase.googleapis.com",
    "container.googleapis.com"
  ]
}
