#!/usr/bin/env bash
# ==============================================================================
# COMMON UTILITIES & ENVIRONMENT LOADER
# ==============================================================================

set -euo pipefail

# Colores para terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Directorios base
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Cargar variables de entorno desde .env
if [ -f "$PROJECT_ROOT/.env" ]; then
    # shellcheck disable=SC1091
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
else
    echo -e "${YELLOW}[!] Advertencia: No se encontró el archivo .env en $PROJECT_ROOT. Usando valores por defecto.${NC}"
fi

# Valores por defecto si no existen en .env
CONTAINER_NAME="${CONTAINER_NAME:-pz-server}"
SERVER_NAME="${SERVER_NAME:-pzserver}"
DATA_PATH="${DATA_PATH:-$PROJECT_ROOT/data}"
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
GAME_PORT="${GAME_PORT:-16261}"
DIRECT_PORT="${DIRECT_PORT:-16262}"
RCON_PORT="${RCON_PORT:-27015}"

# Detectar comando docker compose
if docker compose version &>/dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
else
    DOCKER_COMPOSE_CMD="docker compose"
fi

# Funciones de logging
log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_header() {
    echo -e "\n${BOLD}${BLUE}=== $1 ===${NC}\n"
}

# Verificar si el contenedor está corriendo
is_container_running() {
    if command -v docker &>/dev/null; then
        local status
        status="$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || echo "false")"
        [ "$status" = "true" ]
    else
        return 1
    fi
}

# Ejecutar consulta SQLite de forma segura con Python3 o sqlite3
run_sqlite_query() {
    local db_path="$1"
    local query="$2"

    if [ ! -f "$db_path" ]; then
        return 1
    fi

    if command -v python3 &>/dev/null; then
        python3 -c "
import sqlite3, sys
try:
    conn = sqlite3.connect('$db_path')
    cursor = conn.cursor()
    cursor.execute('''$query''')
    for row in cursor.fetchall():
        print('|'.join(str(x) if x is not None else '' for x in row))
except Exception as e:
    sys.exit(1)
"
    elif command -v sqlite3 &>/dev/null; then
        sqlite3 -separator '|' "$db_path" "$query"
    else
        log_error "No se encontró ni python3 ni sqlite3 para consultar la base de datos."
        return 1
    fi
}
