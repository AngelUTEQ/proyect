from flask import Flask, jsonify, request

app = Flask(__name__)

users = [
    {"id": 1, "username": "user1", "email": "user1@email.com"},
    {"id": 2, "username": "user2", "email": "user2@email.com"}
]

@app.route('/users', methods=['GET'])
def get_users():
    return jsonify({"users": users})

@app.route('/users/<int:user_id>', methods=['GET'])
def get_user(user_id):
    user = next((user for user in users if user['id'] == user_id), None)
    if user is None:
        return jsonify({'error': 'User not found'}), 404
    return jsonify({"user": user})

@app.route('/users', methods=['POST'])
def create_user():
    if not request.json or 'username' not in request.json or 'email' not in request.json:
        return jsonify({'error': 'Missing username or email'}), 400
    
    # Verificar si el usuario ya existe
    if any(user['username'] == request.json['username'] for user in users):
        return jsonify({'error': 'Username already exists'}), 409
    
    if any(user['email'] == request.json['email'] for user in users):
        return jsonify({'error': 'Email already exists'}), 409
    
    user_id = max([user['id'] for user in users], default=0) + 1
    new_user = {
        'id': user_id,
        'username': request.json['username'],
        'email': request.json['email']
    }
    
    users.append(new_user)
    return jsonify({"user": new_user}), 201

@app.route('/users/<int:user_id>', methods=['PUT'])
def update_user(user_id):
    user = next((user for user in users if user['id'] == user_id), None)
    if user is None:
        return jsonify({'error': 'User not found'}), 404
    if not request.json:
        return jsonify({'error': 'Missing data'}), 400
    
    # Verificar duplicados si se cambia username o email
    if 'username' in request.json and request.json['username'] != user['username']:
        if any(u['username'] == request.json['username'] for u in users if u['id'] != user_id):
            return jsonify({'error': 'Username already exists'}), 409
    
    if 'email' in request.json and request.json['email'] != user['email']:
        if any(u['email'] == request.json['email'] for u in users if u['id'] != user_id):
            return jsonify({'error': 'Email already exists'}), 409
    
    user['username'] = request.json.get('username', user['username'])
    user['email'] = request.json.get('email', user['email'])
    return jsonify({"user": user}), 200

@app.route('/users/<int:user_id>', methods=['DELETE'])
def delete_user(user_id):
    global users
    user = next((user for user in users if user['id'] == user_id), None)
    if user is None:
        return jsonify({'error': 'User not found'}), 404
    users = [user for user in users if user['id'] != user_id]
    return jsonify({"message": "User deleted successfully"}), 200

@app.route('/health', methods=['GET'])
def health():
    return jsonify({
        "service": "user_service",
        "status": "running",
        "total_users": len(users)
    }), 200

if __name__ == '__main__':
    app.run(host="0.0.0.0", port=5002, debug=True)