#!/bin/bash

PROJECT_DIR="$(pwd)"
VENV_DIR="$PROJECT_DIR/venv"
LOG_DIR="$PROJECT_DIR/logs"
TUNNEL_LOG_DIR="$PROJECT_DIR/logs/tunnels"

# Crear directorio de logs
mkdir -p "$LOG_DIR"
mkdir -p "$TUNNEL_LOG_DIR"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Iniciando Microservicios Backend y Túneles ===${NC}"

# Verificar entorno virtual para backend
if [ ! -d "$VENV_DIR" ]; then
    echo -e "${RED}Error: venv no encontrado en $VENV_DIR${NC}"
    echo -e "${YELLOW}Ejecuta: python -m venv venv && source venv/bin/activate && pip install flask requests flask-cors${NC}"
    exit 1
fi

# Activar entorno virtual
source "$VENV_DIR/bin/activate"

# Verificar herramientas de túnel
echo -e "${BLUE}Verificando herramientas de túnel...${NC}"
TUNNEL_TOOL=""

# Verificar cloudflared (para backend)
if command -v cloudflared &> /dev/null; then
    TUNNEL_TOOL="cloudflared"
    echo -e "${GREEN}✓ cloudflared encontrado (será usado para backend)${NC}"
elif command -v ngrok &> /dev/null; then
    TUNNEL_TOOL="ngrok"
    echo -e "${GREEN}✓ ngrok encontrado (será usado para backend)${NC}"
else
    echo -e "${RED}No se encontró ninguna herramienta de túnel (ngrok o cloudflared)${NC}"
    echo -e "${YELLOW}Instala una de las dos:${NC}"
    echo -e "${YELLOW}- ngrok: https://ngrok.com/download${NC}"
    echo -e "${YELLOW}- cloudflared: https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation/${NC}"
    exit 1
fi

# Función para verificar puertos
check_port() {
    local port="$1"
    local service="$2"
    if lsof -i :"$port" > /dev/null 2>&1; then
        echo -e "${RED}Error: Puerto $port ($service) ya está en uso${NC}"
        echo -e "${YELLOW}Usa: lsof -ti:$port | xargs kill -9${NC}"
        exit 1
    fi
}

# Verificar puertos backend
echo -e "${BLUE}Verificando puertos...${NC}"
check_port 5000 "API Gateway"
check_port 5001 "Auth Service"
check_port 5002 "User Service"
check_port 5003 "Task Service"

# Función para iniciar servicios Python
start_service() {
    local service_dir=$1
    local service_name=$2
    local port=$3
    local script_file=$4
    
    echo -e "${YELLOW}Iniciando $service_name en puerto $port...${NC}"
    
    if [ ! -d "$PROJECT_DIR/$service_dir" ]; then
        echo -e "${RED}Error: Directorio $service_dir no encontrado${NC}"
        return 1
    fi
    
    if [ ! -f "$PROJECT_DIR/$service_dir/$script_file" ]; then
        echo -e "${RED}Error: Archivo $script_file no encontrado en $service_dir${NC}"
        return 1
    fi
    
    cd "$PROJECT_DIR/$service_dir" || exit 1
    nohup python "$script_file" > "$LOG_DIR/$service_name.log" 2>&1 &
    local pid=$!
    echo "$pid" > "$LOG_DIR/$service_name.pid"
    
    # Esperar un momento para verificar que el proceso inició correctamente
    sleep 2
    if kill -0 "$pid" 2>/dev/null; then
        echo -e "${GREEN}✓ $service_name iniciado correctamente (PID: $pid)${NC}"
    else
        echo -e "${RED}✗ Error al iniciar $service_name${NC}"
        return 1
    fi
    
    cd "$PROJECT_DIR"
}

# Función para crear túneles con ngrok
create_ngrok_tunnel() {
    local port=$1
    local service_name=$2
    local log_file="$TUNNEL_LOG_DIR/${service_name}-tunnel.log"
    
    echo -e "${PURPLE}🔗 Creando túnel ngrok para $service_name (puerto $port)...${NC}"
    
    # Crear túnel ngrok en background
    nohup ngrok http $port > "$log_file" 2>&1 &
    local tunnel_pid=$!
    echo "$tunnel_pid" > "$TUNNEL_LOG_DIR/${service_name}-tunnel.pid"
    
    # Esperar un poco para que se establezca la conexión
    sleep 5
    
    if kill -0 "$tunnel_pid" 2>/dev/null; then
        echo -e "${GREEN}✓ Túnel ngrok $service_name creado (PID: $tunnel_pid)${NC}"
    else
        echo -e "${RED}✗ Error al crear túnel ngrok $service_name${NC}"
    fi
}

# Función para crear túneles con cloudflared
create_cloudflared_tunnel() {
    local port=$1
    local service_name=$2
    local log_file="$TUNNEL_LOG_DIR/${service_name}-tunnel.log"
    
    echo -e "${PURPLE}🔗 Creando túnel cloudflared para $service_name (puerto $port)...${NC}"
    
    # Crear túnel en background
    nohup cloudflared tunnel --url http://localhost:$port > "$log_file" 2>&1 &
    local tunnel_pid=$!
    echo "$tunnel_pid" > "$TUNNEL_LOG_DIR/${service_name}-tunnel.pid"
    
    # Esperar un poco para que se establezca la conexión
    sleep 3
    
    if kill -0 "$tunnel_pid" 2>/dev/null; then
        echo -e "${GREEN}✓ Túnel cloudflared $service_name creado (PID: $tunnel_pid)${NC}"
    else
        echo -e "${RED}✗ Error al crear túnel cloudflared $service_name${NC}"
    fi
}

# Función para crear túnel según la herramienta
create_tunnel() {
    local port=$1
    local service_name=$2
    local tool=$3
    
    if [ "$tool" = "ngrok" ]; then
        create_ngrok_tunnel $port $service_name
    else
        create_cloudflared_tunnel $port $service_name
    fi
}

# Función para extraer URL del túnel ngrok
extract_ngrok_url() {
    local service_name=$1
    local log_file="$TUNNEL_LOG_DIR/${service_name}-tunnel.log"
    
    if [ -f "$log_file" ]; then
        # Buscar la URL en el log de ngrok
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
        # Buscar la URL en el log
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

# Función para extraer URL según la herramienta
extract_tunnel_url() {
    local service_name=$1
    local tool=$2
    
    if [ "$tool" = "ngrok" ]; then
        extract_ngrok_url $service_name
    else
        extract_cloudflared_url $service_name
    fi
}

# Iniciar servicios en orden
echo -e "${BLUE}Iniciando servicios backend...${NC}"

start_service "auth_service" "auth_service" 5001 "app.py"
sleep 1
start_service "user_service" "user_service" 5002 "app.py"
sleep 1
start_service "task_services" "task_services" 5003 "app.py"
sleep 1
start_service "api_gateway" "api_gateway" 5000 "app.py"

echo -e "${GREEN}=== Todos los servicios backend iniciados ===${NC}"

# Esperar un poco más para que los servicios estén completamente listos
echo -e "${YELLOW}Esperando que los servicios estén completamente listos (10s)...${NC}"
sleep 10

# Crear túneles
echo -e "${BLUE}=== Creando túneles públicos ===${NC}"

echo -e "${PURPLE}Creando túneles para backend con $TUNNEL_TOOL...${NC}"
create_tunnel 5000 "api_gateway" "$TUNNEL_TOOL"
sleep 2
create_tunnel 5001 "auth_service" "$TUNNEL_TOOL"
sleep 2
create_tunnel 5002 "user_service" "$TUNNEL_TOOL"
sleep 2
create_tunnel 5003 "task_services" "$TUNNEL_TOOL"

echo -e "${PURPLE}Esperando que se establezcan las conexiones (15s)...${NC}"
sleep 15

echo -e "${GREEN}=== SERVICIOS LOCALES ===${NC}"
echo -e "${GREEN}API Gateway:${NC}        http://127.0.0.1:5000"
echo -e "${GREEN}Auth Service:${NC}       http://127.0.0.1:5001"
echo -e "${GREEN}User Service:${NC}       http://127.0.0.1:5002"
echo -e "${GREEN}Task Service:${NC}       http://127.0.0.1:5003"

echo ""
echo -e "${CYAN}=== SERVICIOS PÚBLICOS (TÚNELES) ===${NC}"
echo -e "${CYAN}API Gateway:${NC}        $(extract_tunnel_url 'api_gateway' "$TUNNEL_TOOL")"
echo -e "${CYAN}Auth Service:${NC}       $(extract_tunnel_url 'auth_service' "$TUNNEL_TOOL")"
echo -e "${CYAN}User Service:${NC}       $(extract_tunnel_url 'user_service' "$TUNNEL_TOOL")"
echo -e "${CYAN}Task Service:${NC}       $(extract_tunnel_url 'task_services' "$TUNNEL_TOOL")"

echo ""
echo -e "${YELLOW}=== Endpoints de prueba (LOCALES) ===${NC}"
echo -e "${GREEN}Health checks:${NC}"
echo "curl http://127.0.0.1:5000/"
echo "curl http://127.0.0.1:5001/health"
echo "curl http://127.0.0.1:5002/health"
echo "curl http://127.0.0.1:5003/health"

echo ""
echo -e "${GREEN}Login:${NC}"
echo 'curl -X POST http://127.0.0.1:5000/auth/login -H "Content-Type: application/json" -d '"'"'{"username":"user1","password":"pass1"}'"'"

echo ""
echo -e "${YELLOW}=== Para el Frontend Angular ===${NC}"
echo -e "${BLUE}Inicia Angular por separado:${NC}"
echo "cd frontend"
echo "ng serve --host 0.0.0.0 --port 4200 --disable-host-check"
echo ""
echo -e "${BLUE}Después crea túnel para frontend:${NC}"
echo "ngrok http 4200"
echo "# o"
echo "cloudflared tunnel --url http://localhost:4200"

echo ""
echo -e "${YELLOW}=== Scripts útiles ===${NC}"
echo -e "${BLUE}Ver URLs actuales:${NC}     ./get-tunnel-urls.sh"
echo -e "${BLUE}Logs de servicios:${NC}     ls -la $LOG_DIR/*.log"
echo -e "${BLUE}Logs de túneles:${NC}       ls -la $TUNNEL_LOG_DIR/*.log"
echo -e "${BLUE}Detener todo:${NC}          ./stop_services.sh"

echo ""
echo -e "${GREEN}¡Todos los servicios backend están corriendo y son accesibles públicamente!${NC}"
echo -e "${PURPLE}🌐 Inicia tu frontend Angular por separado${NC}"
echo -e "${YELLOW}Los túneles se mantendrán activos hasta que cierres este script con Ctrl+C${NC}"

# Función de limpieza
cleanup() {
    echo ""
    echo -e "${YELLOW}🛑 Cerrando servicios y túneles...${NC}"
    
    # Matar túneles
    if [ -d "$TUNNEL_LOG_DIR" ]; then
        for pid_file in "$TUNNEL_LOG_DIR"/*.pid; do
            if [ -f "$pid_file" ]; then
                pid=$(cat "$pid_file")
                kill "$pid" 2>/dev/null
                rm -f "$pid_file"
            fi
        done
    fi
    
    # Matar servicios (usar tu stop_services.sh si existe)
    if [ -f "./stop_services.sh" ]; then
        ./stop_services.sh
    else
        for pid_file in "$LOG_DIR"/*.pid; do
            if [ -f "$pid_file" ]; then
                pid=$(cat "$pid_file")
                kill "$pid" 2>/dev/null
                rm -f "$pid_file"
            fi
        done
    fi
    
    echo -e "${GREEN}✓ Limpieza completada${NC}"
    exit 0
}

# Capturar Ctrl+C para limpieza
trap cleanup SIGINT

# Mantener el script corriendo para que los túneles permanezcan activos
echo ""
echo -e "${PURPLE}Presiona Ctrl+C para cerrar todos los servicios y túneles${NC}"
wait