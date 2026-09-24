#!/usr/bin/env bash
# ==============================================================================
# SERVER STATUS & HEALTH CHECK SCRIPT
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

log_header "ESTADO DEL CONTENEDOR DOCKER ($CONTAINER_NAME)"

if command -v docker &>/dev/null; then
    cd "$PROJECT_ROOT"
    $DOCKER_COMPOSE_CMD ps
else
    log_error "Docker no está disponible en este sistema."
    exit 1
fi

if is_container_running; then
    echo -e "\n${BOLD}📊 Métricas de Rendimiento en Tiempo Real:${NC}"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}" "$CONTAINER_NAME" 2>/dev/null || true

    log_header "PUERTOS Y RED"
    echo -e "${BOLD}Mapeo de puertos en contenedor:${NC}"
    docker port "$CONTAINER_NAME" 2>/dev/null || true

    log_header "JUGADORES CONECTADOS"
    LATEST_USER_LOG="$(find "$DATA_PATH/Logs" -name "*_user.txt" -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | awk '{print $2}' || true)"
    if [ -n "$LATEST_USER_LOG" ] && [ -f "$LATEST_USER_LOG" ]; then
        python3 -c "
import re
connected = set()
with open('$LATEST_USER_LOG', 'r', encoding='utf-8', errors='ignore') as f:
    for line in f:
        m_c = re.search(r'\"([^\"]+)\"\s+fully connected', line)
        if m_c: connected.add(m_c.group(1))
        m_d = re.search(r'\"([^\"]+)\"\s+disconnected player', line)
        if m_d: connected.discard(m_d.group(1))
if connected:
    print('  Jugadores Online (' + str(len(connected)) + '): ' + ', '.join(sorted(connected)))
else:
    print('  0 jugadores conectados actualmente.')
"
    fi

    log_header "ÚLTIMOS EVENTOS / ERRORES EN LOGS"
    CONSOLE_LOG="$DATA_PATH/server-console.txt"
    if [ -f "$CONSOLE_LOG" ]; then
        echo -e "${BOLD}Últimas 5 advertencias o errores registrados:${NC}"
        grep -En "ERROR|Exception|OutOfMemoryError|FATAL|WARN" "$CONSOLE_LOG" | tail -n 5 || echo "No se registraron errores críticos recientes."
    fi
else
    log_warn "El contenedor $CONTAINER_NAME no está en ejecución actualmente."
    echo "Puedes iniciarlo ejecutando: $DOCKER_COMPOSE_CMD up -d"
fi
