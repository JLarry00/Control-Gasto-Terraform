import base64
import json
import os
from google.cloud import service_usage_v1
from google.cloud import billing_v1  # Asegúrate de tenerlo en requirements.txt
from google.api_core import exceptions

def _get_allowed_apis() -> set:
    raw = os.environ.get("APIS_TO_DISABLE_ON_BUDGET", "[]")
    try:
        return set(json.loads(raw))
    except:
        return set()

def _disable_api(project_id: str, service_id: str) -> bool:
    """PLAN A: Apagado suave de la API."""
    client = service_usage_v1.ServiceUsageClient()
    name = f"projects/{project_id}/services/{service_id}"
    try:
        operation = client.disable_service(request={"name": name})
        operation.result(timeout=60)
        return True
    except Exception as e:
        print(f"Error en Plan A: {e}")
        return False

def _disable_api_force(project_id: str, service_id: str) -> bool:
    """PLAN B: Apagado forzoso (con dependencias)."""
    client = service_usage_v1.ServiceUsageClient()
    name = f"projects/{project_id}/services/{service_id}"
    try:
        # El parámetro clave es disable_dependent_services
        operation = client.disable_service(
            request={"name": name, "disable_dependent_services": True}
        )
        operation.result(timeout=60)
        return True
    except Exception as e:
        print(f"Error en Plan B: {e}")
        return False

def _disable_project_billing(project_id: str) -> bool:
    """PLAN C: Botón Nuclear - Desvincular facturación del proyecto."""
    try:
        client = billing_v1.CloudBillingClient()
        name = f"projects/{project_id}"
        # Enviar nombre vacío desvincula la tarjeta de crédito
        billing_info = billing_v1.ProjectBillingInfo(billing_account_name="")
        client.update_project_billing_info(name=name, project_billing_info=billing_info)
        return True
    except Exception as e:
        print(f"¡ERROR CRÍTICO! Falló incluso el botón nuclear: {e}")
        return False

# --- ESTA ES LA FIRMA QUE ACEPTA 1 O 2 ARGUMENTOS ---
def budget_guard(data, context=None):
    """
    Función flexible:
    - Si context es None: Se llamó como Gen 2 (CloudEvent).
    - Si context tiene valor: Se llamó como Gen 1 (data, context).
    """
    project_id = os.environ.get("GCP_PROJECT")
    alert_threshold = float(os.environ.get("BUDGET_ALERT_THRESHOLD", "0"))
    allowed = _get_allowed_apis()

    # --- Lógica de extracción de datos robusta ---
    try:
        # Caso Gen 2 (CloudEvent de Pub/Sub)
        if hasattr(data, "data") and isinstance(data.data, dict) and "message" in data.data:
            pubsub_data = data.data["message"].get("data")
        # Caso Gen 1 o test de Pub/Sub antiguo
        elif isinstance(data, dict) and "data" in data:
            pubsub_data = data["data"]
        else:
            print("Formato de mensaje no reconocido")
            return "Formato desconocido", 200

        decoded_payload = base64.b64decode(pubsub_data).decode("utf-8")
        payload = json.loads(decoded_payload)
    except Exception as e:
        print(f"Error decodificando el mensaje: {e}")
        return "Error de decodificación", 200

    # Comprobación de umbral
    is_alert = payload.get("alertThresholdExceeded") is not None or (
        float(payload.get("costAmount", 0)) >= alert_threshold * float(payload.get("budgetAmount", 0))
    )
    
    if not is_alert:
        print("Costo dentro de límites. No se requiere acción.")
        return "OK", 200

    api_to_disable = (payload.get("budgetDisplayName") or "").strip()
    if api_to_disable not in allowed:
        print(f"API {api_to_disable} no está en la lista de control.")
        return "Ignorado", 200

    # --- ESCALERA DE PÁNICO ---
    print(f"¡ALERTA! Superado presupuesto de {api_to_disable}. Iniciando mitigación.")
    
    if _disable_api(project_id, api_to_disable):
        print(f"Éxito: API {api_to_disable} deshabilitada suavemente.")
    else:
        print("Plan A falló. Iniciando Plan B (Forzado)...")
        if _disable_api_force(project_id, api_to_disable):
            print(f"Éxito: API {api_to_disable} deshabilitada forzosamente.")
        else:
            print("Plan B falló. ¡ACTIVANDO BOTÓN NUCLEAR!")
            if _disable_project_billing(project_id):
                print("FACTURACIÓN DESHABILITADA PARA EL PROYECTO.")
            else:
                # Si llegamos aquí, lanzamos excepción para que Pub/Sub reintente
                raise Exception("Fallo total en todas las medidas de contención.")

    return "Procesado correctamente", 200