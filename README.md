# Control-Gasto-Terraform

Proyecto para evitar subidas repentinas de costes en Google Cloud usando Terraform.

Este repositorio despliega la **infraestructura de control de presupuesto** sobre las APIs que usa tu infraestructura de servicios. Hay **un presupuesto por API**; cuando **solo esa API** se pasa de su presupuesto, se deshabilita **solo esa API** (no el resto). Así evitas que un servicio dispare el gasto y se apague todo el proyecto.

## Servicios controlados por defecto

- Cloud Run, Vertex AI, BigQuery, Firebase, Kubernetes (GKE).  
  Para ampliar: añade entradas en `terraform.tfvars`, en: `api_to_billing_service_id` y en `apis_to_control_on_budget_exceeded`.

## Qué despliega este Terraform

1. **APIs necesarias** para el control: Billing Budgets, Pub/Sub, Cloud Run, Service Usage, etc.
2. **Un presupuesto por API** (cada uno filtra por servicio de facturación), con alertas al 50 %, 90 % y 100 %.
3. **Topic de Pub/Sub** donde Billing publica las notificaciones.
4. **Cloud Function** que, al recibir una alerta, lee `budgetDisplayName` (= API id del presupuesto que se superó) y **deshabilita solo esa API** vía Service Usage.

## IDs de servicio de facturación

Cada presupuesto se filtra por **servicio de facturación** (formato `XXXX-XXXX-XXXX`). Esos IDs **no** son los de Service Usage (`run.googleapis.com`); se obtienen en **Billing > Informes** o con la [Catalog API](https://cloud.google.com/billing/docs/how-tos/catalog-api). Configura el mapa `api_to_billing_service_id` en `variables.tf` o en `terraform.tfvars` (los valores por defecto son ejemplos; conviene verificar en tu cuenta).

## Cómo usar

1. Copia `terraform.tfvars.example` a `terraform.tfvars` y rellena `project_id`, `billing_account_id` y, si hace falta, `api_to_billing_service_id`.
2. `terraform init` → `terraform plan` → `terraform apply`

Cuando **una** API supere su presupuesto, Billing enviará una notificación con el nombre de ese presupuesto; la función deshabilita únicamente esa API. Para volver a habilitarla: consola GCP (Service Usage) o tu propio Terraform.

## Ámbito temporal de control

- Instantáneo: control de subidas repentinas de gasto y capacidad de respuesta en tiempo real.
