from flask import Flask, request, jsonify
import sqlite3
from functools import wraps
import requests
from datetime import datetime

app = Flask(__name__)
app.config['DEBUG'] = True

AUTH_SERVICE_URL = "http://127.0.0.1:5001/validate_token"

def token_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        token = request.headers.get('Authorization')
        if not token:
            return jsonify({"error": "Token requerido"}), 401

        # Limpiar el Bearer si viene en el token
        if token.startswith('Bearer '):
            token = token[7:]

        try:
            response = requests.post(AUTH_SERVICE_URL, json={"token": token})
            if response.status_code != 200:
                return jsonify({"error": "Token inválido o expirado"}), 403
            
            # Guardar información del usuario en g para uso posterior
            user_info = response.json()
            request.current_user = user_info
        except Exception as e:
            return jsonify({"error": f"Error de comunicación con el servicio de autenticación: {str(e)}"}), 500

        return f(*args, **kwargs)
    return decorated

def init_db():
    conn = sqlite3.connect("database.db")
    cursor = conn.cursor()
    cursor.execute("PRAGMA foreign_keys = ON")

    # Tabla de estados
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS STATUS (
            id_status INTEGER PRIMARY KEY AUTOINCREMENT,
            status_name TEXT UNIQUE NOT NULL
        )
    """)

    # Tabla de tareas
    cursor.execute(""" 
        CREATE TABLE IF NOT EXISTS TASKS (
            id_task INTEGER PRIMARY KEY AUTOINCREMENT,
            name_task TEXT NOT NULL,
            desc_task TEXT,
            created_of DATE NOT NULL,
            deadline DATE,
            status INTEGER NOT NULL,
            isActive BOOLEAN DEFAULT 1,
            Created_by TEXT NOT NULL,
            FOREIGN KEY (status) REFERENCES STATUS(id_status)
        )
    """)

    # Insertar estados por defecto si no existen
    cursor.execute("SELECT COUNT(*) FROM STATUS")
    if cursor.fetchone()[0] == 0:
        cursor.executemany("INSERT INTO STATUS (status_name) VALUES (?)", [
            ('In progress',),
            ('Revision',),
            ('Completed',),
            ('Paused',)
        ])

    # Insertar tareas de ejemplo si no existen
    cursor.execute("SELECT COUNT(*) FROM TASKS")
    if cursor.fetchone()[0] == 0:
        cursor.executemany("""
            INSERT INTO TASKS (name_task, desc_task, created_of, deadline, status, isActive, Created_by)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """, [
            ('Task 1', 'Task 1 description', '2024-01-01', '2024-01-05', 1, 1, 'user1'),
            ('Task 2', 'Task 2 description', '2024-01-01', '2024-01-05', 2, 1, 'user1'),
            ('Task 3', 'Task 3 description', '2024-01-01', '2024-01-05', 3, 1, 'user1'),
            ('Task 4', 'Task 4 description', '2024-01-01', '2024-01-05', 1, 1, 'user2'),
        ])

    conn.commit()
    conn.close()

@app.route('/tasks', methods=['GET'])
@token_required
def get_tasks():
    conn = sqlite3.connect("database.db")
    cursor = conn.cursor()
    
    # Join con STATUS para obtener el nombre del estado
    cursor.execute("""
        SELECT t.id_task, t.name_task, t.desc_task, t.created_of, t.deadline, 
               s.status_name, t.isActive, t.Created_by
        FROM TASKS t
        JOIN STATUS s ON t.status = s.id_status
        WHERE t.isActive = 1
    """)
    
    tasks = []
    for row in cursor.fetchall():
        tasks.append({
            'id_task': row[0],
            'name_task': row[1],
            'desc_task': row[2],
            'created_of': row[3],
            'deadline': row[4],
            'status': row[5],
            'isActive': bool(row[6]),
            'Created_by': row[7]
        })
    
    conn.close()
    return jsonify({"tasks": tasks})

@app.route('/tasks/<int:id_task>', methods=['GET'])
@token_required
def get_task(id_task):
    conn = sqlite3.connect("database.db")
    cursor = conn.cursor()
    
    cursor.execute("""
        SELECT t.id_task, t.name_task, t.desc_task, t.created_of, t.deadline, 
               s.status_name, t.isActive, t.Created_by
        FROM TASKS t
        JOIN STATUS s ON t.status = s.id_status
        WHERE t.id_task = ?
    """, (id_task,))
    
    row = cursor.fetchone()
    conn.close()
    
    if row:
        task = {
            'id_task': row[0],
            'name_task': row[1],
            'desc_task': row[2],
            'created_of': row[3],
            'deadline': row[4],
            'status': row[5],
            'isActive': bool(row[6]),
            'Created_by': row[7]
        }
        return jsonify({"task": task})
    else:
        return jsonify({"error": "Task not found"}), 404

@app.route('/tasks', methods=['POST'])
@token_required
def create_task():
    data = request.json
    required_fields = ["name_task", "desc_task", "deadline", "status"]
    
    if not all(k in data for k in required_fields):
        return jsonify({'error': f'Missing required fields: {required_fields}'}), 400

    conn = sqlite3.connect("database.db")
    cursor = conn.cursor()
    
    # Verificar que el status existe
    cursor.execute("SELECT id_status FROM STATUS WHERE id_status = ?", (data['status'],))
    if not cursor.fetchone():
        conn.close()
        return jsonify({'error': 'Invalid status ID'}), 400
    
    # Obtener usuario actual del token
    created_by = getattr(request, 'current_user', {}).get('username', 'unknown')
    created_of = datetime.now().strftime('%Y-%m-%d')
    
    cursor.execute("""
        INSERT INTO TASKS (name_task, desc_task, created_of, deadline, status, isActive, Created_by)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    """, (
        data['name_task'], 
        data['desc_task'], 
        created_of, 
        data['deadline'],
        data['status'], 
        data.get('isActive', True), 
        created_by
    ))
    
    task_id = cursor.lastrowid
    conn.commit()
    conn.close()
    
    return jsonify({'message': 'Task created successfully', 'task_id': task_id}), 201

@app.route('/tasks/<int:id_task>', methods=['PUT'])
@token_required
def update_task(id_task):
    data = request.json
    if not data:
        return jsonify({'error': 'No data provided'}), 400
    
    conn = sqlite3.connect("database.db")
    cursor = conn.cursor()
    
    # Verificar que la tarea existe
    cursor.execute("SELECT * FROM TASKS WHERE id_task = ?", (id_task,))
    if cursor.fetchone() is None:
        conn.close()
        return jsonify({'error': 'Task not found'}), 404
    
    # Verificar status si se proporciona
    if 'status' in data:
        cursor.execute("SELECT id_status FROM STATUS WHERE id_status = ?", (data['status'],))
        if not cursor.fetchone():
            conn.close()
            return jsonify({'error': 'Invalid status ID'}), 400
    
    # Construir query dinámicamente
    update_fields = []
    values = []
    
    for field in ['name_task', 'desc_task', 'deadline', 'status', 'isActive']:
        if field in data:
            update_fields.append(f"{field} = ?")
            values.append(data[field])
    
    if update_fields:
        values.append(id_task)
        query = f"UPDATE TASKS SET {', '.join(update_fields)} WHERE id_task = ?"
        cursor.execute(query, values)
    
    conn.commit()
    conn.close()
    return jsonify({'message': 'Task updated successfully'}), 200

@app.route('/tasks/<int:id_task>', methods=['DELETE'])
@token_required
def delete_task(id_task):
    conn = sqlite3.connect("database.db")
    cursor = conn.cursor()
    
    # Verificar que la tarea existe
    cursor.execute("SELECT * FROM TASKS WHERE id_task = ?", (id_task,))
    if cursor.fetchone() is None:
        conn.close()
        return jsonify({'error': 'Task not found'}), 404
    
    # Soft delete - marcar como inactiva
    cursor.execute("UPDATE TASKS SET isActive = 0 WHERE id_task = ?", (id_task,))
    conn.commit()
    conn.close()
    return jsonify({'message': 'Task deleted successfully'}), 200

@app.route('/status', methods=['GET'])
def get_status():
    conn = sqlite3.connect("database.db")
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM STATUS")
    status_list = [{'id': row[0], 'name': row[1]} for row in cursor.fetchall()]
    conn.close()
    return jsonify({"status": status_list})

@app.route('/health', methods=['GET'])
def health():
    conn = sqlite3.connect("database.db")
    cursor = conn.cursor()
    cursor.execute("SELECT COUNT(*) FROM TASKS WHERE isActive = 1")
    active_tasks = cursor.fetchone()[0]
    conn.close()
    
    return jsonify({
        "service": "task_service",
        "status": "running",
        "active_tasks": active_tasks
    }), 200

if __name__ == '__main__':
    init_db()
    app.run(host="0.0.0.0", port=5003, debug=True)