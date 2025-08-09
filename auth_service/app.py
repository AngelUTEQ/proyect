from flask import Flask, jsonify, request
import time
import uuid
import hashlib
import pyotp

app = Flask(__name__)

users = []
tokens = {}
TOKEN_EXPIRATION_SECONDS = 600  # 10 minutos

def hash_password(password: str) -> str:
    return hashlib.sha256(password.encode()).hexdigest()

@app.route('/register', methods=['POST'])
def register():
    data = request.get_json()
    if not data or 'username' not in data or 'password' not in data:
        return jsonify({'error': 'Missing username or password'}), 400
    
    username = data['username']
    password = data['password']

    # Verificar si el usuario ya existe
    if any(user['username'] == username for user in users):
        return jsonify({'error': 'Username already exists'}), 409

    password_hash = hash_password(password)

    # Generar secreto OTP para Google Authenticator
    secret = pyotp.random_base32()

    user_id = len(users) + 1
    new_user = {
        'id': user_id,
        'username': username,
        'password_hash': password_hash,
        'otp_secret': secret
    }
    users.append(new_user)

    # Crear URL OTP para el QR
    otp_auth_url = pyotp.totp.TOTP(secret).provisioning_uri(name=username, issuer_name="MiApp")

    return jsonify({
        'message': 'User registered successfully',
        'user_id': user_id,
        'otpAuthUrl': otp_auth_url
    }), 201

@app.route('/login', methods=['POST'])
def login():
    data = request.get_json()
    if not data or 'username' not in data or 'password' not in data or 'otp' not in data:
        return jsonify({'error': 'Missing username, password or otp'}), 400
    
    username = data['username']
    password = data['password']
    otp_code = data['otp']

    user = next((u for u in users if u['username'] == username), None)
    if not user:
        return jsonify({'error': 'Invalid username or password'}), 401

    if user['password_hash'] != hash_password(password):
        return jsonify({'error': 'Invalid username or password'}), 401

    # Validar OTP
    totp = pyotp.TOTP(user['otp_secret'])
    if not totp.verify(otp_code):
        return jsonify({'error': 'Invalid or expired OTP code'}), 401

    # Generar token
    token = str(uuid.uuid4())
    expires = time.time() + TOKEN_EXPIRATION_SECONDS
    tokens[token] = {
        "user_id": user['id'],
        "username": username,
        "expires": expires
    }

    return jsonify({
        "message": "Logged in successfully",
        "token": token,
        "user_id": user['id'],
        "username": username
    }), 200

@app.route('/validate_token', methods=['POST'])
def validate_token():
    data = request.json
    if not data or 'token' not in data:
        return jsonify({"error": "Token required"}), 400
    
    token = data.get("token")
    if token.startswith('Bearer '):
        token = token[7:]
    
    if token not in tokens:
        return jsonify({"error": "Invalid token"}), 403
    
    if time.time() > tokens[token]['expires']:
        del tokens[token]
        return jsonify({"error": "Token expired"}), 403
    
    return jsonify({
        "message": "Token valid",
        "user_id": tokens[token]['user_id'],
        "username": tokens[token]['username']
    }), 200

@app.route('/logout', methods=['POST'])
def logout():
    data = request.json
    if not data or 'token' not in data:
        return jsonify({"error": "Token required"}), 400
    
    token = data.get("token")
    if token.startswith('Bearer '):
        token = token[7:]
    
    if token in tokens:
        del tokens[token]
        return jsonify({"message": "Logged out successfully"}), 200
    else:
        return jsonify({"error": "Token not found"}), 404

@app.route('/health', methods=['GET'])
def health():
    return jsonify({
        "service": "auth_service",
        "status": "running",
        "active_tokens": len(tokens)
    }), 200

if __name__ == '__main__':
    app.run(host="0.0.0.0", port=5001, debug=True)
