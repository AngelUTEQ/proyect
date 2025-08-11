#!/bin/bash

# start_termux_no_root.sh - Script optimizado para Termux sin permisos root

PROJECT_DIR="$(pwd)"
VENV_DIR="$PROJECT_DIR/venv"
LOG_DIR="$PROJECT_DIR/logs"
PID_DIR="$PROJECT_DIR/pids"

# Crear directorios necesarios
mkdir -p "$LOG_DIR" "$PID_DIR"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}=== Microservicios para Termux (Sin Root) ===${NC}"

# Verificar Python
if ! command -v python &> /dev/null; then
    echo -e "${RED}❌ Python no encontrado${NC}"
    echo -e "${YELLOW}Instala con: pkg install python${NC}"
    exit 1
fi

# Crear entorno virtual si no existe
if [ ! -d "$VENV_DIR" ]; then
    echo -e "${YELLOW}Creando entorno virtual...${NC}"
    python -m venv venv
fi

# Activar entorno virtual
echo -e "${YELLOW}Activando entorno virtual...${NC}"
source "$VENV_DIR/bin/activate"

# Instalar dependencias
echo -e "${YELLOW}Verificando dependencias Python...${NC}"
pip install --quiet flask requests flask-cors 2>/dev/null

# Función para limpiar procesos anteriores (método Termux)
cleanup_previous() {
    echo -e "${BLUE}Limpiando procesos anteriores...${NC}"
    
    # Método 1: Por PID files
    for pid_file in "$PID_DIR"/*.pid; do
        if [ -f "$pid_file" ]; then
            pid=$(cat "$pid_file" 2>/dev/null)
            if [ ! -z "$pid" ]; then
                kill "$pid" 2>/dev/null || true
            fi
            rm -f "$pid_file"
        fi
    done
    
    # Método 2: Buscar procesos Python con app.py
    pkill -f "python.*app\.py" 2>/dev/null || true
    
    # Método 3: Por nombre de proceso
    for service in api_gateway auth_service user_service task_services; do
        pkill -f "$service" 2>/dev/null || true
    done
    
    sleep 2
    echo -e "${GREEN}✓ Limpieza completada${NC}"
}

# Función para iniciar servicio (método simplificado)
start_service_termux() {
    local service_dir=$1
    local service_name=$2
    local port=$3
    
    echo -e "${YELLOW}Iniciando $service_name en puerto $port...${NC}"
    
    if [ ! -d "$service_dir" ]; then
        echo -e "${RED}✗ Directorio $service_dir no encontrado${NC}"
        return 1
    fi
    
    if [ ! -f "$service_dir/app.py" ]; then
        echo -e "${RED}✗ $service_dir/app.py no encontrado${NC}"
        return 1
    fi
    
    # Cambiar al directorio del servicio
    cd "$service_dir" || return 1
    
    # Iniciar el servicio en background
    python app.py > "$LOG_DIR/$service_name.log" 2>&1 &
    local pid=$!
    
    # Guardar PID
    echo "$pid" > "$PID_DIR/$service_name.pid"
    
    # Volver al directorio principal
    cd "$PROJECT_DIR"
    
    # Verificar que inició (método simple)
    sleep 3
    if kill -0 "$pid" 2>/dev/null; then
        echo -e "${GREEN}✓ $service_name iniciado (PID: $pid)${NC}"
        return 0
    else
        echo -e "${RED}✗ Error al iniciar $service_name${NC}"
        echo -e "${RED}Ver log: tail $LOG_DIR/$service_name.log${NC}"
        return 1
    fi
}

# Función para verificar si un servicio responde
test_service() {
    local url=$1
    local name=$2
    
    if command -v curl &> /dev/null; then
        if curl -s --connect-timeout 5 "$url" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ $name responde${NC}"
        else
            echo -e "${YELLOW}⚠ $name no responde aún${NC}"
        fi
    else
        echo -e "${BLUE}ℹ curl no disponible para probar $name${NC}"
    fi
}

# Función para crear túnel simple
create_simple_tunnel() {
    local port=$1
    local service_name=$2
    
    echo -e "${PURPLE}🔗 Creando túnel para $service_name (puerto $port)${NC}"
    
    if command -v cloudflared &> /dev/null; then
        echo -e "${BLUE}Usando cloudflared...${NC}"
        cloudflared tunnel --url http://localhost:$port > "$LOG_DIR/${service_name}_tunnel.log" 2>&1 &
        local tunnel_pid=$!
        echo "$tunnel_pid" > "$PID_DIR/${service_name}_tunnel.pid"
        
        echo -e "${GREEN}✓ Túnel cloudflared iniciado para $service_name${NC}"
        echo -e "${CYAN}Ver URL en: tail -f $LOG_DIR/${service_name}_tunnel.log${NC}"
        
    elif command -v ngrok &> /dev/null; then
        echo -e "${BLUE}Usando ngrok...${NC}"
        ngrok http $port > "$LOG_DIR/${service_name}_tunnel.log" 2>&1 &
        local tunnel_pid=$!
        echo "$tunnel_pid" > "$PID_DIR/${service_name}_tunnel.pid"
        
        echo -e "${GREEN}✓ Túnel ngrok iniciado para $service_name${NC}"
        echo -e "${CYAN}Ver URL en: tail -f $LOG_DIR/${service_name}_tunnel.log${NC}"
    else
        echo -e "${YELLOW}⚠ No hay herramientas de túnel disponibles${NC}"
        echo -e "${BLUE}Servicio disponible solo localmente: http://127.0.0.1:$port${NC}"
    fi
}

# Limpiar procesos anteriores
cleanup_previous

# Iniciar servicios uno por uno
echo -e "${BLUE}=== Iniciando servicios ===${NC}"

services_started=0

if start_service_termux "auth_service" "auth_service" 5001; then
    services_started=$((services_started + 1))
fi

if start_service_termux "user_service" "user_service" 5002; then
    services_started=$((services_started + 1))
fi

if start_service_termux "task_services" "task_services" 5003; then
    services_started=$((services_started + 1))
fi

if start_service_termux "api_gateway" "api_gateway" 5000; then
    services_started=$((services_started + 1))
fi

if [ $services_started -eq 0 ]; then
    echo -e "${RED}❌ No se pudo iniciar ningún servicio${NC}"
    exit 1
fi

echo -e "${GREEN}✓ $services_started servicios iniciados${NC}"

# Esperar un poco para que se estabilicen
echo -e "${YELLOW}Esperando estabilización (10s)...${NC}"
sleep 10

# Mostrar servicios locales
echo ""
echo -e "${GREEN}=== SERVICIOS LOCALES ===${NC}"
echo -e "${GREEN}API Gateway:${NC}   http://127.0.0.1:5000"
echo -e "${GREEN}Auth Service:${NC}  http://127.0.0.1:5001"
echo -e "${GREEN}User Service:${NC}  http://127.0.0.1:5002"
echo -e "${GREEN}Task Service:${NC}  http://127.0.0.1:5003"

# Probar servicios
echo ""
echo -e "${BLUE}=== Probando servicios ===${NC}"
test_service "http://127.0.0.1:5000/" "API Gateway"
test_service "http://127.0.0.1:5001/health" "Auth Service"
test_service "http://127.0.0.1:5002/health" "User Service"
test_service "http://127.0.0.1:5003/health" "Task Service"

# Preguntar si crear túneles
echo ""
echo -e "${PURPLE}¿Crear túneles públicos? (y/n)${NC}"
read -r create_tunnels

if [[ "$create_tunnels" =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}=== Creando túneles ===${NC}"
    
    # Solo crear túnel para API Gateway (punto de entrada principal)
    create_simple_tunnel 5000 "api_gateway"
    
    echo ""
    echo -e "${CYAN}=== VER URLs DE TÚNELES ===${NC}"
    echo "tail -f $LOG_DIR/*_tunnel.log"
fi

echo ""
echo -e "${YELLOW}=== COMANDOS ÚTILES ===${NC}"
echo -e "${BLUE}Ver logs:${NC}        tail -f $LOG_DIR/*.log"
echo -e "${BLUE}Ver procesos:${NC}    ps aux | grep python"
echo -e "${BLUE}Detener todo:${NC}    pkill -f 'python.*app.py'"
echo -e "${BLUE}Ver PIDs:${NC}        ls -la $PID_DIR/"

echo ""
echo -e "${GREEN}¡Servicios ejecutándose!${NC}"
echo -e "${PURPLE}Presiona Ctrl+C para detener todo${NC}"

# Función de limpieza
cleanup() {
    echo ""
    echo -e "${YELLOW}🛑 Deteniendo servicios...${NC}"
    
    # Matar por PID files
    for pid_file in "$PID_DIR"/*.pid; do
        if [ -f "$pid_file" ]; then
            pid=$(cat "$pid_file" 2>/dev/null)
            if [ ! -z "$pid" ]; then
                kill "$pid" 2>/dev/null || true
            fi
            rm -f "$pid_file"
        fi
    done
    
    # Matar procesos relacionados
    pkill -f "python.*app\.py" 2>/dev/null || true
    pkill -f "cloudflared" 2>/dev/null || true
    pkill -f "ngrok" 2>/dev/null || true
    
    echo -e "${GREEN}✓ Limpieza completada${NC}"
    exit 0
}

trap cleanup SIGINT

# Loop de mantenimiento
while true; do
    sleep 60
    
    # Verificar que al menos un proceso sigue activo
    if ! pgrep -f "python.*app\.py" > /dev/null; then
        echo -e "${RED}❌ Todos los servicios se cerraron${NC}"
        exit 1
    fi
done
