#!/bin/bash

PROJECT_DIR="$(pwd)"
VENV_DIR="$PROJECT_DIR/venv"
LOG_DIR="$PROJECT_DIR/logs"

# Crear directorio de logs
mkdir -p "$LOG_DIR"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Iniciando Microservicios ===${NC}"

# Verificar entorno virtual
if [ ! -d "$VENV_DIR" ]; then
    echo -e "${RED}Error: venv no encontrado en $VENV_DIR${NC}"
    echo -e "${YELLOW}Ejecuta: python -m venv venv && source venv/bin/activate && pip install flask requests${NC}"
    exit 1
fi

# Activar entorno virtual
source "$VENV_DIR/bin/activate"

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

# Verificar todos los puertos
echo -e "${BLUE}Verificando puertos...${NC}"
check_port 5000 "API Gateway"
check_port 5001 "Auth Service"
check_port 5002 "User Service" 
check_port 5003 "Task Service"

# Función para iniciar servicios
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

# Iniciar servicios en orden
echo -e "${BLUE}Iniciando servicios...${NC}"

start_service "auth_service" "auth_service" 5001 "app.py"
sleep 1
start_service "user_service" "user_service" 5002 "app.py"
sleep 1
start_service "task_services" "task_services" 5003 "app.py"
sleep 1
start_service "api_gateway" "api_gateway" 5000 "app.py"

echo -e "${GREEN}=== Todos los servicios iniciados ===${NC}"
echo -e "${BLUE}Logs guardados en: $LOG_DIR${NC}"
echo -e "${BLUE}PIDs guardados en: $LOG_DIR/*.pid${NC}"

echo ""
echo -e "${YELLOW}=== URLs de los servicios ===${NC}"
echo -e "${GREEN}API Gateway:${NC}    http://127.0.0.1:5000"
echo -e "${GREEN}Auth Service:${NC}   http://127.0.0.1:5001"
echo -e "${GREEN}User Service:${NC}   http://127.0.0.1:5002"
echo -e "${GREEN}Task Service:${NC}   http://127.0.0.1:5003"

echo ""
echo -e "${YELLOW}=== Endpoints de prueba ===${NC}"
echo -e "${GREEN}Health checks:${NC}"
echo "curl http://127.0.0.1:5000/"
echo "curl http://127.0.0.1:5001/health"
echo "curl http://127.0.0.1:5002/health"
echo "curl http://127.0.0.1:5003/health"

echo ""
echo -e "${GREEN}Login:${NC}"
echo 'curl -X POST http://127.0.0.1:5000/auth/login -H "Content-Type: application/json" -d '"'"'{"username":"user1","password":"pass1"}'"'"

echo ""
echo -e "${YELLOW}Para detener los servicios, ejecuta: ./stop_services.sh${NC}"