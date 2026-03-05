"""
Reacciona a alertas de presupuesto por API y deshabilita solo la API cuyo
presupuesto se superó (Service Usage API). Cada presupuesto tiene display_name
= API id, así que budgetDisplayName en el mensaje indica qué API deshabilitar.
"""
import base64
import json
import os
from google.cloud import service_usage_v1
from google.cloud import billing_v1
from google.api_core import exceptions


def _get_allowed_apis() -> set:
    """APIs que esta función puede deshabilitar (env var JSON)."""
    raw = os.environ.get("APIS_TO_DISABLE_ON_BUDGET", "[]")
    try:
        return set(json.loads(raw))
    except json.JSONDecodeError:
        return set()


def _disable_api(project_id: str, service_id: str) -> bool:
    """Deshabilita una API en el proyecto. Devuelve True si tuvo éxito."""
    client = service_usage_v1.ServiceUsageClient()
    name = f"projects/{project_id}/services/{service_id}"
    try:
        operation = client.disable_service(request={"name": name})
        operation.result(timeout=60)
        return True
    except exceptions.GoogleAPICallError as e:
        print(f"Error deshabilitando {service_id}: {e}")
        return False


def _disable_api_force(project_id: str, service_id: str) -> bool:
        return False


def _disable_project_billing(project_id: str) -> bool:
        return False


def budget_guard(event, context):
    """
    Entrada para Pub/Sub (notificación de presupuesto). El payload incluye
    budgetDisplayName = API id del presupuesto que se superó. Deshabilita
    solo esa API si está en la lista permitida.
    """
    project_id = os.environ.get("GCP_PROJECT")
    if not project_id:
        print("GCP_PROJECT no configurado")
        return
    
    alert_threshold = float(os.environ.get("BUDGET_ALERT_THRESHOLD", "0"))
    if alert_threshold == 0:
        print("BUDGET_ALERT_THRESHOLD no configurado")
        return

    allowed = _get_allowed_apis()
    if not allowed:
        print("Ninguna API configurada (APIS_TO_DISABLE_ON_BUDGET)")
        return

    try:
        data = base64.b64decode(event["data"]).decode("utf-8")
        payload = json.loads(data)
    except (KeyError, ValueError) as e:
        print(f"Mensaje no válido: {e}")
        return

    alert = payload.get("alertThresholdExceeded") is not None or (
        float(payload.get("costAmount", 0) or 0)
        >= alert_threshold * float(payload.get("budgetAmount", 0) or 0)
    )
    if not alert:
        print("No es alerta de superación de umbral")
        return

    # Qué presupuesto disparó la alerta = qué API deshabilitar (solo esa)
    api_to_disable = (payload.get("budgetDisplayName") or "").strip()
    if not api_to_disable:
        print("Payload sin budgetDisplayName")
        return
    if api_to_disable not in allowed:
        print(f"API {api_to_disable!r} no está en la lista permitida; no se deshabilita")
        return

    print(f"Presupuesto superado para {api_to_disable}. Deshabilitando solo esa API en {project_id}")
    if _disable_api(project_id, api_to_disable):
        print(f"API deshabilitada: {api_to_disable}")
    else:
        print(f"No se pudo deshabilitar suavemente: {api_to_disable}")
        print(f"Intentando deshabilitar de forma forzosa")
        if _disable_api_force(project_id, api_to_disable):
            print(f"API deshabilitada de forma forzosa: {api_to_disable}")
        else:
            print(f"No se pudo deshabilitar de forma forzosa: {api_to_disable}")
            print(f"Intentando deshabilitar la facturación del proyecto")
            if _disable_project_billing(project_id):
                print(f"Facturación deshabilitada")
            else:
                print(f"No se pudo deshabilitar la facturación del proyecto")