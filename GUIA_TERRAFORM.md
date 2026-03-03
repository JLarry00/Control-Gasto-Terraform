# Guía Terraform: de cero a entender este proyecto

Esta guía explica Terraform desde lo básico y luego recorre **todo** este proyecto para que entiendas cómo funciona de punta a punta.

---

## Parte 1: ¿Qué es Terraform?

**Terraform** es una herramienta de **Infraestructura como Código (IaC)**. En lugar de crear servidores, bases de datos o APIs a mano en la consola de un proveedor (por ejemplo Google Cloud), escribes archivos de texto (`.tf`) que **describen** qué quieres tener. Terraform se conecta al proveedor y **crea o modifica** esos recursos por ti.

- **Ventaja:** el mismo código se puede ejecutar en distintos entornos (desarrollo, producción) y queda registrado en git qué infraestructura tienes.
- **Comandos que usarás:** `terraform init`, `terraform plan`, `terraform apply`.

---

## Parte 2: Conceptos básicos de Terraform

### 2.1 Archivos `.tf`

Cualquier archivo con extensión `.tf` en la carpeta del proyecto forma parte de la configuración. **No importa el nombre** del archivo: Terraform junta todos y los trata como un solo “documento”. Por eso repartimos la lógica en varios archivos (`main.tf`, `variables.tf`, `budget.tf`, etc.) solo para organizarnos.

### 2.2 Bloque `terraform { ... }`

Define requisitos del propio Terraform:

- **required_version:** versión mínima de Terraform (ej. `>= 1.6.0`).
- **required_providers:** qué “plugins” necesita (google, archive, etc.) y de qué versión.
- **backend:** dónde se guarda el **estado** (qué recursos creó Terraform). Aquí usamos `local`, es decir, un archivo `terraform.tfstate` en tu máquina.

### 2.3 Provider (proveedor)

El **provider** es el que habla con un servicio externo (en nuestro caso, Google Cloud). Por ejemplo:

```hcl
provider "google" {
  project = var.project_id
  region  = var.region
}
```

Eso le dice a Terraform: “todas las operaciones que hagas en recursos de Google, hazlas en este proyecto y en esta región”.

### 2.4 Variables (`variable`)

Las variables permiten que la misma configuración sirva para distintos entornos sin tocar el código.

- Se **declaran** en `variables.tf` (nombre, tipo, descripción, opcionalmente `default`).
- Se **asignan** en `terraform.tfvars` o por línea de comandos (`-var "project_id=mi-proyecto"`).
- Se **usan** en el resto del código como `var.project_id`, `var.region`, etc.

### 2.5 Recursos (`resource`)

Un **recurso** es “una cosa concreta” en el proveedor: un bucket, un topic de Pub/Sub, una función, etc.

```hcl
resource "google_pubsub_topic" "budget_notifications" {
  name    = "budget-notifications"
  project = var.project_id
}
```

- **Tipo:** `google_pubsub_topic` (tipo de recurso del provider Google).
- **Nombre local:** `budget_notifications` (nombre que usas dentro de Terraform para referirte a él).
- **Argumentos:** propiedades del recurso (`name`, `project`, etc.).

En otros archivos puedes referenciar este topic como `google_pubsub_topic.budget_notifications.id` o `.name`.

### 2.6 Datos (`data`)

Un **data source** no crea nada: **lee** información que ya existe (por ejemplo el proyecto actual).

```hcl
data "google_project" "current" {
  project_id = var.project_id
}
```

Luego usas `data.google_project.current.number` para obtener el número del proyecto, etc.

### 2.7 Locals (`locals`)

Son “constantes” o expresiones que quieres usar en varios sitios sin repetir la lógica.

```hcl
locals {
  control_apis = ["billingbudgets.googleapis.com", "pubsub.googleapis.com", ...]
}
```

Se usan como `local.control_apis`.

### 2.8 Dependencias (`depends_on`)

Indicas que un recurso debe crearse **después** de otros. Por ejemplo: “el presupuesto depende de que las APIs estén habilitadas”.

### 2.9 Estado (state)

Terraform guarda en el **estado** la lista de recursos que ha creado y sus IDs reales en GCP. Así sabe si debe crear un recurso nuevo o actualizar uno existente. Con backend `local`, ese estado está en `terraform.tfstate`.

---

## Parte 3: Flujo de este proyecto (qué hace de punta a punta)

En alto nivel, lo que hace este Terraform es:

1. **Un presupuesto por API**: cada API que quieras controlar tiene su **propio** presupuesto (filtrado por servicio de facturación). No hay un solo presupuesto de proyecto.
2. **Alertas** cuando el gasto de **esa** API pase ciertos porcentajes (50 %, 90 %, 100 %). Billing publica en un **topic de Pub/Sub**.
3. La **Cloud Function** lee el mensaje: el payload incluye **budgetDisplayName** = el API id del presupuesto que se superó. La función **deshabilita solo esa API** (no todas) vía Service Usage.

Así, si solo Cloud Run se pasa de su límite, se apaga solo Cloud Run; el resto sigue activo.

En forma de diagrama:

```
  [Presupuesto API A]   [Presupuesto API B]   ...
        │                      │
        │ "API A superó 90 %"  │
        ▼                      ▼
  [Topic Pub/Sub: budget-notifications]
        │
        │ mensaje con budgetDisplayName = "run.googleapis.com"
        ▼
  [Cloud Function: budget_guard]
        │
        │ deshabilita solo run.googleapis.com
        ▼
  [Solo esa API deshabilitada]
```

Todo lo que está entre corchetes son recursos que **crea o configura** este Terraform.

---

## Parte 4: Archivo por archivo

### 4.1 `main.tf`

- **terraform { }:** versión, providers (google, archive), backend local.
- **provider "google":** proyecto y región por defecto (vienen de variables).
- **data "google_project" "current":** obtiene datos del proyecto (por ejemplo el **número** de proyecto, que Billing y el topic necesitan en algunos sitios).

Aquí no se crean recursos de negocio; solo se configura el “entorno” de Terraform y se lee el proyecto.

---

### 4.2 `variables.tf`

Declara **todas** las variables que usa el proyecto:


| Variable                             | Uso                                                                                                                                 |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------- |
| `project_id`                         | Proyecto GCP donde se despliega todo.                                                                                                |
| `billing_account_id`                 | Cuenta de facturación (para crear los presupuestos).                                                                                |
| `region`                             | Región (Cloud Run, función, bucket).                                                                                                |
| `budget_amount` / `budget_currency`  | Límite de cada presupuesto (ej. 100 EUR por API).                                                                                    |
| `budget_alert_thresholds`            | Porcentajes de alerta (ej. 0.5, 0.9, 1.0 → 50 %, 90 %, 100 %).                                                                      |
| `api_to_billing_service_id`          | Mapa API id → ID de servicio de facturación; se crea un presupuesto por entrada, filtrado por ese servicio.                          |
| `apis_to_control_on_budget_exceeded` | Lista de APIs que la función **puede** deshabilitar; solo deshabilita la que venga en `budgetDisplayName` cuando su presupuesto se supere. |


Los `default` hacen que, si no pones nada en `terraform.tfvars`, esos valores se usen igual.

---

### 4.3 `apis.tf`

**Objetivo:** activar en el proyecto las APIs de GCP que **esta** infraestructura de control necesita (no las de tu aplicación).

- **locals.control_apis:** lista de IDs de API (Billing Budgets, Pub/Sub, Cloud Run, Service Usage, Storage, Eventarc, Cloud Build).
- **resource "google_project_service" "control_apis":** con `for_each = toset(local.control_apis)` se crea **un recurso por cada** API. Cada uno hace “habilitar esta API en el proyecto”.  
`disable_on_destroy = false` indica que, si borras el recurso con Terraform, no se deshabilita la API al destruir (evitas apagados por error).

Sin estas APIs, el presupuesto, el topic, la función y los permisos no podrían crearse o funcionar.

---

### 4.4 `pubsub.tf`

**Objetivo:** tener un topic donde Billing pueda publicar las notificaciones de presupuesto.

- **google_pubsub_topic "budget_notifications":** crea el topic `budget-notifications` en tu proyecto.
- **google_pubsub_topic_iam_member "billing_publisher":** da a la **cuenta de servicio de Cloud Billing** el rol `roles/pubsub.publisher` sobre ese topic. Sin esto, Billing no podría publicar y nunca llegarían mensajes.

El presupuesto (en `budget.tf`) luego indica “envía las notificaciones a este topic”.

---

### 4.5 `budget.tf`

**Objetivo:** crear **un presupuesto por API** (uno por entrada en `api_to_billing_service_id`), cada uno filtrando solo el gasto de ese servicio, y enviar las alertas al mismo topic.

- **for_each = var.api_to_billing_service_id:** un recurso `google_billing_budget` por cada API que quieras controlar.
- **display_name = each.key:** el nombre del presupuesto es el **API id** (ej. `run.googleapis.com`). La notificación de Billing incluye `budgetDisplayName`; la función usa ese valor para saber **qué API** deshabilitar (solo esa).
- **budget_filter.projects:** limita al proyecto actual.
- **budget_filter.services:** limita el gasto al **servicio de facturación** (el valor del mapa, formato `services/XXXX-XXXX-XXXX`). Así cada presupuesto solo “ve” el gasto de esa API.
- **amount**, **threshold_rules**, **all_updates_rule:** igual que antes; todas las notificaciones van al mismo topic.

Cuando **una** API supera su umbral, Billing publica un mensaje con `budgetDisplayName` = ese API id; la función deshabilita solo esa API.

---

### 4.6 `function.tf`

**Objetivo:** empaquetar el código de la función, subirlo a un bucket, crear la cuenta de servicio con permisos para deshabilitar APIs y desplegar la Cloud Function que reacciona al topic.

1. **data "archive_file" "budget_guard_zip":** crea un zip con el contenido de `functions/budget_guard/` (el código Python).
2. **google_storage_bucket "function_source":** bucket donde se guarda ese zip (el nombre incluye proyecto y número para que sea único).
3. **google_storage_bucket_object "budget_guard_zip":** sube el zip al bucket. El nombre del objeto incluye un hash del contenido para que, si cambias el código, Terraform detecte el cambio y actualice la función.
4. **google_service_account "budget_guard":** cuenta de servicio que ejecutará la función.
5. **google_project_iam_member "budget_guard_service_usage":** le da a esa cuenta el rol `roles/serviceusage.serviceUsageAdmin` en el proyecto, que es lo que permite **deshabilitar** APIs.
6. **google_cloudfunctions2_function "budget_guard":**
  - **build_config:** runtime Python 3.12, código desde el zip en el bucket, función de entrada `budget_guard`.
  - **service_config:** memoria, tiempo máximo, cuenta de servicio, y **variables de entorno:** `GCP_PROJECT` y `APIS_TO_DISABLE_ON_BUDGET` (la lista de APIs en JSON, la misma que `var.apis_to_control_on_budget_exceeded`).
  - **event_trigger:** tipo “mensaje publicado en un topic de Pub/Sub”, topic = el de `budget_notifications`. Así, cada vez que Billing publica, se ejecuta la función.

La función **no** crea ni destruye recursos en Terraform; solo se ejecuta cuando llega un mensaje, lee **budgetDisplayName** del payload (el API id del presupuesto que se superó) y, si está en la lista permitida, deshabilita **solo esa API**.

---

### 4.7 `functions/budget_guard/main.py`

Es el **código** que corre dentro de la Cloud Function (no es Terraform).

- **budget_guard(event, context):** es la función que Cloud Run/Functions invoca cuando llega un mensaje de Pub/Sub.
- **event["data"]:** el cuerpo del mensaje viene en base64; se decodifica y se parsea como JSON (es el formato de notificación de Billing).
- Comprueba si es una alerta de “umbral superado” (`alertThresholdExceeded` o comparando `costAmount` con `budgetAmount`).
- Lee **budgetDisplayName** del payload (es el API id del presupuesto que se superó, porque en `budget.tf` pusimos `display_name = each.key`).
- Si ese API id está en la lista permitida (`APIS_TO_DISABLE_ON_BUDGET`), llama a **Service Usage API** (`disable_service`) para deshabilitar **solo esa API**.

Así, cada presupuesto controla una API; cuando salta la alerta, se deshabilita únicamente la API correspondiente.

---

### 4.8 `outputs.tf`

Los **outputs** son valores que Terraform muestra al final de `apply` (y que puedes consultar con `terraform output`). Aquí se exportan cosas como el topic, el nombre de la función y la lista de APIs controladas, para que puedas verificar o usar esos datos en scripts sin buscarlos a mano.

---

## Parte 5: Cómo se ejecuta todo (orden real)

Cuando ejecutas comandos, Terraform **no** sigue el orden de los archivos; sigue el **grafo de dependencias** entre recursos. En la práctica:

1. **terraform init:** descarga providers y configura el backend (estado).
2. **terraform plan:** lee el estado actual, compara con los `.tf` y te dice qué va a crear, cambiar o destruir (sin hacer nada aún).
3. **terraform apply:** hace los cambios. El orden típico sería:
  - Habilita las APIs (`apis.tf`).
  - Crea el topic y su IAM (`pubsub.tf`).
  - Crea el presupuesto y lo enlaza al topic (`budget.tf`).
  - Crea el zip, el bucket, el objeto, la cuenta de servicio, el permiso de Service Usage y la Cloud Function (`function.tf`).

Las `depends_on` y las referencias entre recursos (por ejemplo `pubsub_topic = google_pubsub_topic.budget_notifications.id`) fuerzan ese orden.

---

## Parte 6: Resumen en una frase por archivo


| Archivo                          | En una frase                                                                                                                                           |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `main.tf`                        | Configura Terraform, el provider de Google y lee los datos del proyecto.                                                                               |
| `variables.tf`                   | Define todos los parámetros configurables (proyecto, presupuesto, lista de APIs a controlar).                                                          |
| `apis.tf`                        | Habilita las APIs de GCP que necesita esta infraestructura de control.                                                                                 |
| `pubsub.tf`                      | Crea el topic de Pub/Sub y da permiso a Billing para publicar en él.                                                                                   |
| `budget.tf`                      | Crea el presupuesto del proyecto y manda las alertas a ese topic.                                                                                      |
| `function.tf`                    | Empaqueta el código, crea la cuenta de servicio con permiso para deshabilitar APIs y despliega la función que escucha el topic y deshabilita **solo la API** indicada en `budgetDisplayName`. |
| `outputs.tf`                     | Muestra topic, función y lista de APIs controladas al final del apply.                                                                                 |
| `functions/budget_guard/main.py` | Código Python que, al recibir una alerta de presupuesto, deshabilita las APIs configuradas vía Service Usage.                                          |


---

## Parte 7: Qué hacer cuando tengas acceso a GCP

1. Copia `terraform.tfvars.example` a `terraform.tfvars`.
2. Rellena `project_id` y `billing_account_id` (el ID de facturación lo ves en la consola de Billing).
3. Ejecuta:
  - `terraform init`
  - `terraform plan` (revisa qué va a crear)
  - `terraform apply` (confirma con `yes` si todo es correcto)
4. Cuando quieras **ampliar** las APIs controladas, solo añade o quita IDs en `apis_to_control_on_budget_exceeded` (en `variables.tf` o en `terraform.tfvars`) y vuelve a hacer `terraform apply`.

Con esto tienes desde lo básico de Terraform hasta el flujo completo de este proyecto. Si quieres profundizar en un archivo o bloque concreto, se puede bajar al detalle línea por línea.