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

# Verificar conexión a internet
echo -e "${BLUE}Verificando conexión a internet...${NC}"
if ! ping -c 1 google.com &> /dev/null; then
    echo -e "${RED}❌ Sin conexión a internet. Verifica tu conexión.${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Conexión a internet OK${NC}"

# Verificar entorno virtual para backend
if [ ! -d "$VENV_DIR" ]; then
    echo -e "${RED}Error: venv no encontrado en $VENV_DIR${NC}"
    echo -e "${YELLOW}Ejecuta: python -m venv venv && source venv/bin/activate && pip install flask requests flask-cors${NC}"
    exit 1
fi

# Activar entorno virtual
source "$VENV_DIR/bin/activate"

# Verificar herramientas de túnel con prioridad mejorada
echo -e "${BLUE}Verificando herramientas de túnel...${NC}"
TUNNEL_TOOL=""
BACKUP_TUNNEL=""

# Verificar ngrok primero (más estable para múltiples túneles)
if command -v ngrok &> /dev/null; then
    TUNNEL_TOOL="ngrok"
    echo -e "${GREEN}✓ ngrok encontrado (será usado como principal)${NC}"
fi

# Verificar cloudflared como backup
if command -v cloudflared &> /dev/null; then
    if [ -z "$TUNNEL_TOOL" ]; then
        TUNNEL_TOOL="cloudflared"
        echo -e "${GREEN}✓ cloudflared encontrado (será usado como principal)${NC}"
    else
        BACKUP_TUNNEL="cloudflared"
        echo -e "${GREEN}✓ cloudflared encontrado (disponible como backup)${NC}"
    fi
fi

if [ -z "$TUNNEL_TOOL" ]; then
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
        echo -e "${YELLOW}Deteniéndolo automáticamente...${NC}"
        lsof -ti:"$port" | xargs kill -9 2>/dev/null || true
        sleep 2
    fi
}

# Verificar y limpiar puertos backend
echo -e "${BLUE}Verificando puertos...${NC}"
check_port 5000 "API Gateway"
check_port 5001 "Auth Service"
check_port 5002 "User Service"
check_port 5003 "Task Service"

# Función para iniciar servicios Python con mejor manejo de errores
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
    
    # Iniciar el servicio con mejor logging
    nohup python "$script_file" > "$LOG_DIR/$service_name.log" 2>&1 &
    local pid=$!
    echo "$pid" > "$LOG_DIR/$service_name.pid"
    
    # Esperar y verificar múltiples veces
    local retries=5
    local started=false
    
    for ((i=1; i<=retries; i++)); do
        sleep 2
        if kill -0 "$pid" 2>/dev/null; then
            # Verificar si el puerto está escuchando
            if lsof -i :"$port" > /dev/null 2>&1; then
                echo -e "${GREEN}✓ $service_name iniciado correctamente (PID: $pid, Puerto: $port)${NC}"
                started=true
                break
            fi
        fi
        echo -e "${YELLOW}⏳ Reintento $i/$retries para $service_name...${NC}"
    done
    
    if [ "$started" = false ]; then
        echo -e "${RED}✗ Error al iniciar $service_name después de $retries intentos${NC}"
        echo -e "${RED}Revisa el log: tail -f $LOG_DIR/$service_name.log${NC}"
        return 1
    fi
    
    cd "$PROJECT_DIR"
}

# Función para crear túneles con ngrok mejorada
create_ngrok_tunnel() {
    local port=$1
    local service_name=$2
    local log_file="$TUNNEL_LOG_DIR/${service_name}-tunnel.log"
    
    echo -e "${PURPLE}🔗 Creando túnel ngrok para $service_name (puerto $port)...${NC}"
    
    # Limpiar log anterior
    > "$log_file"
    
    # Crear túnel ngrok en background
    nohup ngrok http $port --log=stdout --log-level=info > "$log_file" 2>&1 &
    local tunnel_pid=$!
    echo "$tunnel_pid" > "$TUNNEL_LOG_DIR/${service_name}-tunnel.pid"
    
    # Esperar y verificar el túnel
    local max_wait=15
    local count=0
    
    while [ $count -lt $max_wait ]; do
        sleep 1
        count=$((count + 1))
        
        if ! kill -0 "$tunnel_pid" 2>/dev/null; then
            echo -e "${RED}✗ Error: túnel ngrok $service_name se cerró inesperadamente${NC}"
            return 1
        fi
        
        # Buscar URL en el log
        if grep -q "started tunnel" "$log_file" 2>/dev/null; then
            echo -e "${GREEN}✓ Túnel ngrok $service_name establecido (PID: $tunnel_pid)${NC}"
            return 0
        fi
    done
    
    echo -e "${YELLOW}⚠ Túnel ngrok $service_name tardando más de lo esperado${NC}"
    return 0
}

# Función para crear túneles con cloudflared mejorada
create_cloudflared_tunnel() {
    local port=$1
    local service_name=$2
    local log_file="$TUNNEL_LOG_DIR/${service_name}-tunnel.log"
    
    echo -e "${PURPLE}🔗 Creando túnel cloudflared para $service_name (puerto $port)...${NC}"
    
    # Limpiar log anterior
    > "$log_file"
    
    # Intentar crear túnel con timeout
    timeout 30 cloudflared tunnel --url http://localhost:$port > "$log_file" 2>&1 &
    local tunnel_pid=$!
    echo "$tunnel_pid" > "$TUNNEL_LOG_DIR/${service_name}-tunnel.pid"
    
    # Esperar y verificar
    local max_wait=20
    local count=0
    
    while [ $count -lt $max_wait ]; do
        sleep 1
        count=$((count + 1))
        
        # Verificar si el proceso sigue activo
        if ! kill -0 "$tunnel_pid" 2>/dev/null; then
            echo -e "${RED}✗ Error: túnel cloudflared $service_name falló${NC}"
            # Mostrar últimas líneas del error
            echo -e "${RED}Últimos errores:${NC}"
            tail -5 "$log_file" 2>/dev/null || echo "No hay logs disponibles"
            return 1
        fi
        
        # Buscar URL exitosa
        if grep -q "https://.*\.trycloudflare\.com" "$log_file" 2>/dev/null; then
            echo -e "${GREEN}✓ Túnel cloudflared $service_name establecido (PID: $tunnel_pid)${NC}"
            return 0
        fi
        
        # Verificar errores conocidos
        if grep -q "dial tcp.*lookup.*trycloudflare" "$log_file" 2>/dev/null; then
            echo -e "${RED}✗ Error de DNS/conectividad en cloudflared para $service_name${NC}"
            kill "$tunnel_pid" 2>/dev/null
            return 1
        fi
    done
    
    echo -e "${YELLOW}⚠ Túnel cloudflared $service_name tardando más de lo esperado${NC}"
    return 0
}

# Función para crear túnel con fallback
create_tunnel_with_fallback() {
    local port=$1
    local service_name=$2
    
    if [ "$TUNNEL_TOOL" = "ngrok" ]; then
        if ! create_ngrok_tunnel $port $service_name; then
            if [ ! -z "$BACKUP_TUNNEL" ]; then
                echo -e "${YELLOW}🔄 Intentando con $BACKUP_TUNNEL como fallback...${NC}"
                create_cloudflared_tunnel $port $service_name
            fi
        fi
    else
        if ! create_cloudflared_tunnel $port $service_name; then
            if [ ! -z "$BACKUP_TUNNEL" ]; then
                echo -e "${YELLOW}🔄 Intentando con ngrok como fallback...${NC}"
                create_ngrok_tunnel $port $service_name
            fi
        fi
    fi
}

# Función para extraer URL del túnel ngrok mejorada
extract_ngrok_url() {
    local service_name=$1
    local log_file="$TUNNEL_LOG_DIR/${service_name}-tunnel.log"
    
    if [ -f "$log_file" ]; then
        local url=$(grep -o 'https://[^[:space:]]*\.ngrok[^[:space:]]*' "$log_file" 2>/dev/null | head -1)
        if [ ! -z "$url" ]; then
            echo "$url"
        else
            # Buscar también en formato JSON de ngrok v3
            local url_json=$(grep -o '"public_url":"https://[^"]*"' "$log_file" 2>/dev/null | cut -d'"' -f4 | head -1)
            if [ ! -z "$url_json" ]; then
                echo "$url_json"
            else
                echo "⏳ Estableciendo..."
            fi
        fi
    else
        echo "❌ Log no disponible"
    fi
}

# Función para extraer URL del túnel cloudflared mejorada
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
        echo "❌ Log no disponible"
    fi
}

# Función para extraer URL según la herramienta
extract_tunnel_url() {
    local service_name=$1
    
    # Intentar con ambas herramientas
    local ngrok_url=$(extract_ngrok_url $service_name)
    local cloudflared_url=$(extract_cloudflared_url $service_name)
    
    if [[ "$ngrok_url" =~ ^https:// ]]; then
        echo "$ngrok_url"
    elif [[ "$cloudflared_url" =~ ^https:// ]]; then
        echo "$cloudflared_url"
    else
        echo "⏳ Estableciendo..."
    fi
}

# Iniciar servicios en orden
echo -e "${BLUE}=== Iniciando servicios backend ===${NC}"

if ! start_service "auth_service" "auth_service" 5001 "app.py"; then
    echo -e "${RED}❌ Falló auth_service, continuando con los demás...${NC}"
fi
sleep 2

if ! start_service "user_service" "user_service" 5002 "app.py"; then
    echo -e "${RED}❌ Falló user_service, continuando con los demás...${NC}"
fi
sleep 2

if ! start_service "task_services" "task_services" 5003 "app.py"; then
    echo -e "${RED}❌ Falló task_services, continuando con los demás...${NC}"
fi
sleep 2

if ! start_service "api_gateway" "api_gateway" 5000 "app.py"; then
    echo -e "${RED}❌ Falló api_gateway${NC}"
fi

echo -e "${GREEN}=== Servicios backend iniciados ===${NC}"

# Esperar que los servicios estén completamente listos
echo -e "${YELLOW}Esperando que los servicios estén completamente listos (5s)...${NC}"
sleep 5

# Verificar cuáles servicios están realmente corriendo
echo -e "${BLUE}=== Verificando servicios activos ===${NC}"
declare -a active_services=()

for port_service in "5000:api_gateway" "5001:auth_service" "5002:user_service" "5003:task_services"; do
    port=$(echo $port_service | cut -d: -f1)
    service=$(echo $port_service | cut -d: -f2)
    
    if lsof -i :"$port" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ $service (puerto $port)${NC}"
        active_services+=("$port:$service")
    else
        echo -e "${RED}✗ $service (puerto $port)${NC}"
    fi
done

# Solo crear túneles para servicios activos
if [ ${#active_services[@]} -gt 0 ]; then
    echo -e "${BLUE}=== Creando túneles para servicios activos ===${NC}"
    
    for service_info in "${active_services[@]}"; do
        port=$(echo $service_info | cut -d: -f1)
        service=$(echo $service_info | cut -d: -f2)
        
        create_tunnel_with_fallback $port $service
        sleep 3  # Esperar entre túneles para evitar rate limiting
    done
    
    echo -e "${PURPLE}Esperando que se establezcan completamente los túneles (10s)...${NC}"
    sleep 10
    
else
    echo -e "${RED}❌ No hay servicios activos para crear túneles${NC}"
    exit 1
fi

# Mostrar información de servicios
echo ""
echo -e "${GREEN}=== SERVICIOS LOCALES ===${NC}"
echo -e "${GREEN}API Gateway:${NC}        http://127.0.0.1:5000"
echo -e "${GREEN}Auth Service:${NC}       http://127.0.0.1:5001"
echo -e "${GREEN}User Service:${NC}       http://127.0.0.1:5002"
echo -e "${GREEN}Task Service:${NC}       http://127.0.0.1:5003"


echo ""
echo -e "${YELLOW}=== Comandos útiles ===${NC}"
echo -e "${BLUE}Ver URLs actualizadas:${NC}"
echo "watch -n 5 './get-tunnel-urls.sh'"
echo ""
echo -e "${BLUE}Logs en tiempo real:${NC}"
echo "tail -f $LOG_DIR/*.log"
echo "tail -f $TUNNEL_LOG_DIR/*.log"
echo ""
echo -e "${BLUE}Health checks:${NC}"
echo "curl -s http://127.0.0.1:5000/ || echo 'API Gateway no responde'"
echo "curl -s http://127.0.0.1:5001/health || echo 'Auth Service no responde'"
echo ""
echo -e "${BLUE}Detener todo:${NC}"
echo "./stop_services.sh"

echo ""
echo -e "${GREEN}¡Sistema iniciado! Usa Ctrl+C para detener todo${NC}"

# Función de limpieza mejorada
cleanup() {
    echo ""
    echo -e "${YELLOW}🛑 Iniciando limpieza...${NC}"
    
    # Matar túneles
    echo -e "${YELLOW}Cerrando túneles...${NC}"
    if [ -d "$TUNNEL_LOG_DIR" ]; then
        for pid_file in "$TUNNEL_LOG_DIR"/*.pid; do
            if [ -f "$pid_file" ]; then
                pid=$(cat "$pid_file" 2>/dev/null)
                if [ ! -z "$pid" ]; then
                    kill -TERM "$pid" 2>/dev/null || true
                    sleep 1
                    kill -KILL "$pid" 2>/dev/null || true
                fi
                rm -f "$pid_file"
            fi
        done
    fi
    
    # Matar servicios
    echo -e "${YELLOW}Cerrando servicios...${NC}"
    if [ -f "./stop_services.sh" ]; then
        ./stop_services.sh
    else
        for pid_file in "$LOG_DIR"/*.pid; do
            if [ -f "$pid_file" ]; then
                pid=$(cat "$pid_file" 2>/dev/null)
                if [ ! -z "$pid" ]; then
                    kill -TERM "$pid" 2>/dev/null || true
                    sleep 1
                    kill -KILL "$pid" 2>/dev/null || true
                fi
                rm -f "$pid_file"
            fi
        done
    fi
    
    # Limpiar puertos si es necesario
    for port in 5000 5001 5002 5003; do
        lsof -ti:"$port" | xargs kill -9 2>/dev/null || true
    done
    
    echo -e "${GREEN}✓ Limpieza completada${NC}"
    exit 0
}

# Capturar señales para limpieza
trap cleanup SIGINT SIGTERM

# Mantener el script corriendo
echo ""
echo -e "${PURPLE}Los servicios están corriendo. Presiona Ctrl+C para cerrar todo${NC}"
echo -e "${CYAN}Tip: Abre otra terminal para seguir trabajando${NC}"

echo ""
echo -e "${CYAN}=== SERVICIOS PÚBLICOS (TÚNELES) ===${NC}"
echo -e "${CYAN}API Gateway:${NC}        $(extract_tunnel_url 'api_gateway')"
echo -e "${CYAN}Auth Service:${NC}       $(extract_tunnel_url 'auth_service')"
echo -e "${CYAN}User Service:${NC}       $(extract_tunnel_url 'user_service')"
echo -e "${CYAN}Task Service:${NC}       $(extract_tunnel_url 'task_services')"

# Loop infinito con verificación periódica
while true; do
    sleep 30
    # Verificar que al menos un servicio siga activo
    services_running=false
    for port in 5000 5001 5002 5003; do
        if lsof -i :"$port" > /dev/null 2>&1; then
            services_running=true
            break
        fi
    done
    
    if [ "$services_running" = false ]; then
        echo -e "${RED}❌ Todos los servicios se han cerrado inesperadamente${NC}"
        exit 1
    fi
done
