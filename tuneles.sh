#!/bin/bash

PROJECT_DIR="$(pwd)"
TUNNEL_LOG_DIR="$PROJECT_DIR/logs/tunnels"

# Colores para output
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Función para extraer URL del túnel ngrok
extract_ngrok_url() {
    local service_name=$1
    local log_file="$TUNNEL_LOG_DIR/${service_name}-tunnel.log"
    
    if [ -f "$log_file" ]; then
        local url=$(grep -o 'https://[^[:space:]]*\.ngrok[^[:space:]]*' "$log_file" 2>/dev/null | head -1)
        if [ ! -z "$url" ]; then
            echo "$url"
        else
            echo "⏳ Estableciendo..."
        fi
    else
        echo "❌ No disponible"
    fi
}

# Función para extraer URL del túnel cloudflared
extract_cloudflared_url() {
    local service_name=$1
    local log_file="$TUNNEL_LOG_DIR/${service_name}-tunnel.log"
    
    if [ -f "$log_file" ]; then
        local url=$(grep -o 'https://[^[:space:]]*\.trycloudflare\.com' "$log_file" 2>/dev/null | head -1)
        if [ ! -z "$url" ]; then
            echo "$url"
        else
            echo "⏳ Estableciendo..."
        fi
    else
        echo "❌ No disponible"
    fi
}

# Función para extraer URL del túnel (detecta automáticamente el tipo)
extract_tunnel_url() {
    local service_name=$1
    local log_file="$TUNNEL_LOG_DIR/${service_name}-tunnel.log"
    
    if [ -f "$log_file" ]; then
        # Intentar ngrok primero
        local url=$(grep -o 'https://[^[:space:]]*\.ngrok[^[:space:]]*' "$log_file" 2>/dev/null | head -1)
        if [ ! -z "$url" ]; then
            echo "$url"
            return
        fi
        
        # Intentar cloudflared
        url=$(grep -o 'https://[^[:space:]]*\.trycloudflare\.com' "$log_file" 2>/dev/null | head -1)
        if [ ! -z "$url" ]; then
            echo "$url"
            return
        fi
        
        echo "⏳ Estableciendo..."
    else
        echo "❌ No disponible"
    fi
}

# Función para verificar si un servicio está corriendo
check_service_status() {
    local service_name=$1
    local pid_file="$PROJECT_DIR/logs/${service_name}.pid"
    
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${GREEN}✓ Activo${NC}"
        else
            echo -e "${RED}✗ Inactivo${NC}"
        fi
    else
        echo -e "${RED}✗ No iniciado${NC}"
    fi
}

echo -e "${CYAN}=== ESTADO DE SERVICIOS Y TÚNELES ===${NC}"
echo ""

echo -e "${YELLOW}Frontend (Angular):${NC}"
echo -e "  Estado: $(check_service_status 'frontend')"
echo -e "  Local:  http://127.0.0.1:4200"
echo -e "  Túnel:  $(extract_tunnel_url 'frontend')"
echo ""

echo -e "${YELLOW}API Gateway:${NC}"
echo -e "  Estado: $(check_service_status 'api_gateway')"
echo -e "  Local:  http://127.0.0.1:5000"
echo -e "  Túnel:  $(extract_tunnel_url 'api_gateway')"
echo ""

echo -e "${YELLOW}Auth Service:${NC}"
echo -e "  Estado: $(check_service_status 'auth_service')"
echo -e "  Local:  http://127.0.0.1:5001"
echo -e "  Túnel:  $(extract_tunnel_url 'auth_service')"
echo ""

echo -e "${YELLOW}User Service:${NC}"
echo -e "  Estado: $(check_service_status 'user_service')"
echo -e "  Local:  http://127.0.0.1:5002"
echo -e "  Túnel:  $(extract_tunnel_url 'user_service')"
echo ""

echo -e "${YELLOW}Task Service:${NC}"
echo -e "  Estado: $(check_service_status 'task_services')"
echo -e "  Local:  http://127.0.0.1:5003"
echo -e "  Túnel:  $(extract_tunnel_url 'task_services')"
echo ""

# Mostrar solo las URLs públicas en formato copiable
echo -e "${CYAN}=== URLs PÚBLICAS (Solo túneles activos) ===${NC}"
frontend_url=$(extract_tunnel_url 'frontend')
api_url=$(extract_tunnel_url 'api_gateway')
auth_url=$(extract_tunnel_url 'auth_service')
user_url=$(extract_tunnel_url 'user_service')
task_url=$(extract_tunnel_url 'task_services')

if [[ "$frontend_url" != "⏳"* && "$frontend_url" != "❌"* ]]; then
    echo -e "${GREEN}Frontend:${NC} $frontend_url"
fi

if [[ "$api_url" != "⏳"* && "$api_url" != "❌"* ]]; then
    echo -e "${GREEN}API Gateway:${NC} $api_url"
fi

if [[ "$auth_url" != "⏳"* && "$auth_url" != "❌"* ]]; then
    echo -e "${GREEN}Auth Service:${NC} $auth_url"
fi

if [[ "$user_url" != "⏳"* && "$user_url" != "❌"* ]]; then
    echo -e "${GREEN}User Service:${NC} $user_url"
fi

if [[ "$task_url" != "⏳"* && "$task_url" != "❌"* ]]; then
    echo -e "${GREEN}Task Service:${NC} $task_url"
fi