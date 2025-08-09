#!/bin/bash

PROJECT_DIR="$(pwd)"
LOG_DIR="$PROJECT_DIR/logs"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Deteniendo Microservicios ===${NC}"

# Función para detener un servicio
stop_service() {
    local service_name=$1
    local pid_file="$LOG_DIR/$service_name.pid"
    
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${YELLOW}Deteniendo $service_name (PID: $pid)...${NC}"
            kill "$pid"
            
            # Esperar a que el proceso termine
            local count=0
            while kill -0 "$pid" 2>/dev/null && [ $count -lt 10 ]; do
                sleep 1
                count=$((count + 1))
            done
            
            if kill -0 "$pid" 2>/dev/null; then
                echo -e "${RED}Forzando detención de $service_name...${NC}"
                kill -9 "$pid"
            fi
            
            echo -e "${GREEN}✓ $service_name detenido${NC}"
        else
            echo -e "${YELLOW}$service_name ya no está ejecutándose${NC}"
        fi
        rm -f "$pid_file"
    else
        echo -e "${YELLOW}No se encontró archivo PID para $service_name${NC}"
    fi
}

# Detener servicios en orden inverso
stop_service "api_gateway"
stop_service "task_services"
stop_service "user_service"
stop_service "auth_service"

# Verificar puertos y forzar cierre si es necesario
echo -e "${BLUE}Verificando puertos...${NC}"
for port in 5000 5001 5002 5003; do
    if lsof -i :"$port" > /dev/null 2>&1; then
        echo -e "${YELLOW}Puerto $port aún en uso, forzando cierre...${NC}"
        lsof -ti:"$port" | xargs kill -9 2>/dev/null
    fi
done

echo -e "${GREEN}=== Todos los servicios detenidos ===${NC}"

# Mostrar logs si hay errores
if [ -d "$LOG_DIR" ]; then
    echo -e "${BLUE}Logs disponibles en: $LOG_DIR${NC}"
    echo -e "${YELLOW}Para ver logs de errores:${NC}"
    echo "tail -n 50 $LOG_DIR/*.log"
fi