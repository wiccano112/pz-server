#!/usr/bin/env bash
# ==============================================================================
# STAGING UTILITIES & ENVIRONMENT LOADER
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGING_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PRD_ROOT="$(cd "$STAGING_ROOT/.." && pwd)"

# Cargar variables de staging
if [ -f "$STAGING_ROOT/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$STAGING_ROOT/.env"
    set +a
else
    echo -e "${YELLOW}[!] Advertencia: No se encontró .env en $STAGING_ROOT. Usando valores por defecto.${NC}"
fi

CONTAINER_NAME="${CONTAINER_NAME:-pz-rpm-server-stg}"
SERVER_NAME="${SERVER_NAME:-pz-rpm-server-stg}"
DATA_PATH="${DATA_PATH:-$STAGING_ROOT/data}"
PRD_DATA_PATH="${PRD_ROOT}/data"
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
GAME_PORT="${GAME_PORT:-17261}"
DIRECT_PORT="${DIRECT_PORT:-17262}"
RCON_PORT="${RCON_PORT:-27025}"
SERVER_BRANCH="${SERVER_BRANCH:-unstable}"

if docker compose version &>/dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
else
    DOCKER_COMPOSE_CMD="docker compose"
fi

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

is_container_running() {
    if command -v docker &>/dev/null; then
        local status
        status="$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null || echo "false")"
        [ "$status" = "true" ]
    else
        return 1
    fi
}
