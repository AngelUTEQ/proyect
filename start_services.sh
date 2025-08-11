#!/bin/bash

PROJECT_DIR="$(pwd)"
VENV_DIR="$PROJECT_DIR/venv"
LOG_DIR="$PROJECT_DIR/logs"
PID_DIR="$PROJECT_DIR/pids"

mkdir -p "$LOG_DIR" "$PID_DIR"

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

# Instalar dependencias (ajusta según tus necesidades)
echo -e "${YELLOW}Instalando dependencias Python...${NC}"
pip install --quiet flask requests flask-cors 2>/dev/null

# Limpiar procesos viejos
echo -e "${BLUE}Limpiando procesos anteriores...${NC}"
for pid_file in "$PID_DIR"/*.pid; do
    [ -f "$pid_file" ] && kill $(cat "$pid_file") 2>/dev/null
    rm -f "$pid_file"
done
pkill -f "python.*app\.py" 2>/dev/null || true
pkill -f "cloudflared" 2>/dev/null || true
pkill -f "ngrok" 2>/dev/null || true
sleep 2

# Función para iniciar un servicio
start_service() {
    local dir=$1
    local name=$2
    local port=$3

    echo -e "${YELLOW}Iniciando $name en puerto $port...${NC}"
    if [ ! -d "$dir" ]; then
        echo -e "${RED}✗ Directorio $dir no encontrado${NC}"
        return 1
    fi
    if [ ! -f "$dir/app.py" ]; then
        echo -e "${RED}✗ $dir/app.py no encontrado${NC}"
        return 1
    fi

    cd "$dir" || return 1
    python app.py > "$LOG_DIR/$name.log" 2>&1 &
    local pid=$!
    echo $pid > "$PID_DIR/$name.pid"
    cd "$PROJECT_DIR" || return 1

    sleep 3
    if kill -0 $pid 2>/dev/null; then
        echo -e "${GREEN}✓ $name iniciado (PID: $pid)${NC}"
        return 0
    else
        echo -e "${RED}✗ Error al iniciar $name${NC}"
        echo -e "${RED}Ver log con: tail -f $LOG_DIR/$name.log${NC}"
        return 1
    fi
}

# Función para crear túnel cloudflared y mostrar URL
create_tunnel() {
    local port=$1
    local name=$2

    echo -e "${PURPLE}🔗 Creando túnel para $name (puerto $port)...${NC}"
    cloudflared tunnel --url http://localhost:$port --no-autoupdate > "$LOG_DIR/${name}_tunnel.log" 2>&1 &
    local tid=$!
    echo $tid > "$PID_DIR/${name}_tunnel.pid"

    # Esperar y extraer URL pública
    for i in {1..15}; do
        sleep 2
        url=$(grep -o 'https://[^ ]*\.trycloudflare\.com' "$LOG_DIR/${name}_tunnel.log" | head -1)
        if [ -n "$url" ]; then
            echo -e "${GREEN}✓ Túnel $name activo en: $url${NC}"
            return 0
        fi
    done

    echo -e "${YELLOW}⚠ No se pudo obtener URL del túnel para $name. Revisa logs:${NC}"
    echo "tail -f $LOG_DIR/${name}_tunnel.log"
    return 1
}

# Iniciar servicios
services=(
    "auth_service 5001"
    "user_service 5002"
    "task_services 5003"
    "api_gateway 5000"
)

started=0
for service in "${services[@]}"; do
    name=$(echo $service | cut -d' ' -f1)
    port=$(echo $service | cut -d' ' -f2)
    if start_service "$name" "$name" "$port"; then
        started=$((started+1))
    fi
done

if [ $started -eq 0 ]; then
    echo -e "${RED}❌ No se inició ningún servicio${NC}"
    exit 1
fi

echo -e "${YELLOW}Esperando 10 segundos para estabilización...${NC}"
sleep 10

# Preguntar si crear túneles
read -p "¿Crear túneles públicos para todos los servicios? (y/n): " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
    for service in "${services[@]}"; do
        name=$(echo $service | cut -d' ' -f1)
        port=$(echo $service | cut -d' ' -f2)
        create_tunnel $port $name
    done
fi

echo -e "${GREEN}✓ Todo listo. Servicios y túneles iniciados.${NC}"
echo -e "${BLUE}Para detener todo presiona Ctrl+C${NC}"

# Función limpieza a la salida
cleanup() {
    echo -e "\n${YELLOW}Deteniendo servicios y túneles...${NC}"
    for pid_file in "$PID_DIR"/*.pid; do
        [ -f "$pid_file" ] && kill $(cat "$pid_file") 2>/dev/null
        rm -f "$pid_file"
    done
    pkill -f "python.*app\.py" 2>/dev/null || true
    pkill -f "cloudflared" 2>/dev/null || true
    pkill -f "ngrok" 2>/dev/null || true
    echo -e "${GREEN}✓ Limpieza completada${NC}"
    exit 0
}
trap cleanup SIGINT

# Mantener el script vivo mientras los procesos corren
while true; do
    sleep 60
    if ! pgrep -f "python.*app\.py" > /dev/null; then
        echo -e "${RED}❌ Todos los servicios se cerraron${NC}"
        exit 1
    fi
done
