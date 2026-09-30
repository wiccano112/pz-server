#!/usr/bin/env bash
# ==============================================================================
# VIEW STAGING LOGS
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

cd "$STAGING_ROOT"

TAIL_LINES="${1:-100}"

echo -e "${CYAN}Mostrando logs de staging ($CONTAINER_NAME)... (Ctrl+C para salir)${NC}\n"
$DOCKER_COMPOSE_CMD logs -f --tail="$TAIL_LINES"
