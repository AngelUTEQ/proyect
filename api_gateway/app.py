from flask import Flask, jsonify, request, g, send_file, make_response
from flask_cors import CORS
import requests
import time
import os
from datetime import datetime, timedelta
from collections import defaultdict
from pymongo import MongoClient
from pymongo.errors import PyMongoError

app = Flask(__name__)

# ✅ ESTA ES LA ÚNICA LÍNEA QUE CAMBIÉ - Permitir tu frontend ngrok
CORS(app, origins=[
    "http://localhost:4200",  # Para desarrollo local
    "https://84ae62a2b981.ngrok-free.app",  # Tu URL específica de frontend
    "https://*.ngrok-free.app",  # Cualquier URL ngrok (por si cambia)
    "https://*.ngrok.io",  # URLs ngrok alternativas
    "*"  # O simplemente "*" para permitir todo (menos seguro pero más fácil)
])

# ✅ AGREGADO: Manejador para peticiones OPTIONS (CORS preflight)
@app.before_request
def handle_preflight():
    if request.method == "OPTIONS":
        response = make_response()
        response.headers.add("Access-Control-Allow-Origin", "*")
        response.headers.add('Access-Control-Allow-Headers', "*")
        response.headers.add('Access-Control-Allow-Methods', "*")
        return response

AUTH_SERVICE_URL = "http://127.0.0.1:5001"
USER_SERVICE_URL = "http://127.0.0.1:5002"
TASK_SERVICE_URL = "http://127.0.0.1:5003"

logs_data = []

# Elimina log anterior al iniciar
LOG_FILENAME = "gateway.log"
if os.path.exists(LOG_FILENAME):
    os.remove(LOG_FILENAME)

# --- MongoDB Setup ---
# Cambia la URI por la tuya, con usuario, clave y cluster correctos
MONGO_URI = "mongodb+srv://root1:root1@cluster0.unmkv5b.mongodb.net/?retryWrites=true&w=majority&appName=Cluster0"
client = MongoClient(MONGO_URI)
db = client.gateway_logs
logs_collection = db.logs

# Mapeo de endpoints a servicios
SERVICE_MAPPING = {
    "auth": "auth-service",
    "users": "user-service",
    "tasks": "task-service",
    "": "gateway-service"  # Para el health check
}

# Obtener usuario desde el token llamando a /validate_token en auth_service
def get_username_from_token(token):
    try:
        resp = requests.post(f"{AUTH_SERVICE_URL}/validate_token", json={"token": token}, timeout=2)
        if resp.status_code == 200:
            return resp.json().get("username", "anon")
    except:
        pass
    return "anon"

def get_service_from_endpoint(endpoint):
    """Determinar el servicio basado en el endpoint"""
    if not endpoint or endpoint == "/":
        return "gateway-service"
    
    path_parts = endpoint.strip("/").split("/")
    service_key = path_parts[0] if path_parts and path_parts[0] else ""
    return SERVICE_MAPPING.get(service_key, f"{service_key}-service")

@app.before_request
def start_timer():
    # Solo ejecutar si no es una petición OPTIONS
    if request.method != "OPTIONS":
        g.start_time = time.time()
        token = request.headers.get("Authorization", "").replace("Bearer ", "")
        g.current_user = get_username_from_token(token)

@app.after_request
def log_request(response):
    if request.path.startswith("/logs") or request.path == "/favicon.ico" or request.method == "OPTIONS":
        return response

    duration = round((time.time() - g.start_time) * 1000)
    service = get_service_from_endpoint(request.path)
    
    log_entry = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "method": request.method,
        "endpoint": request.path,
        "status_code": response.status_code,
        "response_time_ms": duration,
        "user": g.get("current_user", "anon"),
        "service": service
    }

    # Agregar a la lista en memoria
    logs_data.append(log_entry)

    # Guardar en archivo local
    with open(LOG_FILENAME, "a", encoding="utf-8") as f:
        f.write(f"{log_entry['timestamp']} {log_entry['user']} - {log_entry['method']} "
                f"{log_entry['endpoint']} [{log_entry['status_code']}] "
                f"{log_entry['response_time_ms']}ms {service}\n")

    # Guardar en MongoDB (ignorar errores para no interrumpir)
    try:
        logs_collection.insert_one(log_entry)
    except PyMongoError as e:
        print(f"Error guardando log en MongoDB: {e}")

    return response

# Proxies auth, users y tasks (igual que antes)
@app.route("/auth/<path:path>", methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"])
def auth_proxy(path):
    url = f"{AUTH_SERVICE_URL}/{path}"
    headers = {key: value for key, value in request.headers if key.lower() != 'host'}

    try:
        resp = requests.request(
            method=request.method,
            url=url,
            json=request.get_json(silent=True),
            headers=headers
        )
        try:
            data = resp.json()
            return jsonify(data), resp.status_code
        except ValueError:
            return resp.text, resp.status_code
    except requests.exceptions.RequestException as e:
        return jsonify({"error": f"Error en la conexión con auth_service: {str(e)}"}), 502

@app.route("/users/<path:path>", methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"])
def user_proxy(path):
    url = f"{USER_SERVICE_URL}/users/{path}"
    headers = {key: value for key, value in request.headers if key.lower() != 'host'}

    try:
        resp = requests.request(
            method=request.method,
            url=url,
            json=request.get_json(silent=True),
            headers=headers
        )
        try:
            data = resp.json()
            return jsonify(data), resp.status_code
        except ValueError:
            return resp.text, resp.status_code
    except requests.exceptions.RequestException as e:
        return jsonify({"error": f"Error en la conexión con user_service: {str(e)}"}), 502

@app.route("/users", methods=["GET", "POST", "OPTIONS"])
def users_proxy():
    url = f"{USER_SERVICE_URL}/users"
    headers = {key: value for key, value in request.headers if key.lower() != 'host'}

    try:
        resp = requests.request(
            method=request.method,
            url=url,
            json=request.get_json(silent=True),
            headers=headers
        )
        try:
            data = resp.json()
            return jsonify(data), resp.status_code
        except ValueError:
            return resp.text, resp.status_code
    except requests.exceptions.RequestException as e:
        return jsonify({"error": f"Error en la conexión con user_service: {str(e)}"}), 502

@app.route("/tasks/<path:path>", methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"])
def task_proxy(path):
    url = f"{TASK_SERVICE_URL}/tasks/{path}"
    headers = {key: value for key, value in request.headers if key.lower() != 'host'}

    try:
        resp = requests.request(
            method=request.method,
            url=url,
            json=request.get_json(silent=True),
            headers=headers
        )
        try:
            data = resp.json()
            return jsonify(data), resp.status_code
        except ValueError:
            return resp.text, resp.status_code
    except requests.exceptions.RequestException as e:
        return jsonify({"error": f"Error en la conexión con task_service: {str(e)}"}), 502

@app.route("/tasks", methods=["GET", "POST", "OPTIONS"])
def tasks_proxy():
    url = f"{TASK_SERVICE_URL}/tasks"
    headers = {key: value for key, value in request.headers if key.lower() != 'host'}

    try:
        resp = requests.request(
            method=request.method,
            url=url,
            json=request.get_json(silent=True),
            headers=headers
        )
        try:
            data = resp.json()
            return jsonify(data), resp.status_code
        except ValueError:
            return resp.text, resp.status_code
    except requests.exceptions.RequestException as e:
        return jsonify({"error": f"Error en la conexión con task_service: {str(e)}"}), 502

@app.route("/", methods=["GET"])
def health_check():
    return jsonify({
        "message": "API Gateway funcionando",
        "services": {
            "auth_service": f"{AUTH_SERVICE_URL}",
            "user_service": f"{USER_SERVICE_URL}",
            "task_service": f"{TASK_SERVICE_URL}"
        }
    }), 200

# --- Cambié esta ruta para que lea los logs desde MongoDB ---
@app.route("/logs", methods=["GET", "OPTIONS"])
def logs_view():
    limit = int(request.args.get('limit', 50))
    try:
        # Traer logs ordenados por timestamp descendente, limitado por 'limit'
        cursor = logs_collection.find().sort("timestamp", -1).limit(limit)
        logs = list(cursor)
        # Convertir ObjectId a str y asegurarse de tener 'service'
        for log in logs:
            log["_id"] = str(log["_id"])
            if "service" not in log:
                log["service"] = get_service_from_endpoint(log["endpoint"])
        total_count = logs_collection.count_documents({})
        return jsonify({"logs": logs, "total": total_count}), 200
    except PyMongoError as e:
        return jsonify({"error": f"Error consultando logs en MongoDB: {str(e)}"}), 500

@app.route("/logs/stats", methods=["GET", "OPTIONS"])
def logs_stats():
    if not logs_data:
        return jsonify({
            "total_api_calls": 0,
            "unique_users": 0,
            "service_statistics": {},
            "status_code_statistics": {},
            "response_time_statistics": {},
            "hourly_stats": {},
            "daily_stats": {},
            "top_endpoints": [],
            "error_rate": 0.0,
            "success_rate": 0.0
        }), 200

    total_calls = len(logs_data)
    users = set(entry['user'] for entry in logs_data)
    services = defaultdict(int)
    status_codes = defaultdict(int)
    response_times = defaultdict(lambda: {
        "total_calls": 0,
        "total_ms": 0,
        "min_ms": float('inf'),
        "max_ms": 0
    })
    
    hourly_stats = defaultdict(int)
    daily_stats = defaultdict(int)
    endpoint_stats = defaultdict(lambda: {"calls": 0, "total_response_time": 0})
    
    success_count = 0
    error_count = 0

    for log in logs_data:
        service = log.get('service', get_service_from_endpoint(log['endpoint']))
        services[service] += 1

        status = str(log['status_code'])
        status_codes[status] += 1

        if 200 <= log['status_code'] < 400:
            success_count += 1
        else:
            error_count += 1

        rt = log['response_time_ms']
        rt_stats = response_times[service]
        rt_stats['total_calls'] += 1
        rt_stats['total_ms'] += rt
        rt_stats['min_ms'] = min(rt_stats['min_ms'], rt)
        rt_stats['max_ms'] = max(rt_stats['max_ms'], rt)

        try:
            log_time = datetime.fromisoformat(log['timestamp'].replace('Z', '+00:00'))
            hour_key = log_time.strftime('%H')
            day_key = log_time.strftime('%Y-%m-%d')
            hourly_stats[hour_key] += 1
            daily_stats[day_key] += 1
        except:
            pass

        endpoint = log['endpoint']
        endpoint_stats[endpoint]["calls"] += 1
        endpoint_stats[endpoint]["total_response_time"] += rt

    for service, stats in response_times.items():
        if stats['total_calls'] > 0:
            stats['avg_ms'] = round(stats['total_ms'] / stats['total_calls'], 2)
        else:
            stats['avg_ms'] = 0

    top_endpoints = []
    for endpoint, stats in endpoint_stats.items():
        avg_response_time = stats["total_response_time"] / stats["calls"] if stats["calls"] > 0 else 0
        top_endpoints.append({
            "endpoint": endpoint,
            "calls": stats["calls"],
            "avg_response_time": round(avg_response_time, 2)
        })

    top_endpoints.sort(key=lambda x: x["calls"], reverse=True)

    success_rate = (success_count / total_calls * 100) if total_calls > 0 else 0
    error_rate = (error_count / total_calls * 100) if total_calls > 0 else 0

    return jsonify({
        "total_api_calls": total_calls,
        "unique_users": len(users),
        "service_statistics": dict(services),
        "status_code_statistics": dict(status_codes),
        "response_time_statistics": dict(response_times),
        "hourly_stats": dict(hourly_stats),
        "daily_stats": dict(daily_stats),
        "top_endpoints": top_endpoints[:10],
        "error_rate": round(error_rate, 2),
        "success_rate": round(success_rate, 2)
    }), 200

@app.route("/logs/download", methods=["GET"])
def download_log_file():
    if os.path.exists(LOG_FILENAME):
        return send_file(LOG_FILENAME, as_attachment=True)
    return jsonify({"error": "No se encontró el archivo de log."}), 404

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000, debug=True)