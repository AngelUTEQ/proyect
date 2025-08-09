from flask import Flask, jsonify, request
from flask_cors import CORS  
import requests

app = Flask(__name__)
CORS(app) 

AUTH_SERVICE_URL = "http://127.0.0.1:5001"
USER_SERVICE_URL = "http://127.0.0.1:5002"
TASK_SERVICE_URL = "http://127.0.0.1:5003"

@app.route("/auth/<path:path>", methods=["GET", "POST", "PUT", "DELETE"])
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

@app.route("/users/<path:path>", methods=["GET", "POST", "PUT", "DELETE"])
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

@app.route("/users", methods=["GET", "POST"])
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

@app.route("/tasks/<path:path>", methods=["GET", "POST", "PUT", "DELETE"])
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

@app.route("/tasks", methods=["GET", "POST"])
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

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=5000, debug=True)