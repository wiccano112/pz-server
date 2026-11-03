#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE REINICIO DIARIO INTELIGENTE PARA PROJECT ZOMBOID
# ==============================================================================
# Verifica que no haya jugadores conectados vía RCON antes de reiniciar.
# Si hay jugadores, espera e intenta nuevamente hasta agotar los intentos.
# ==============================================================================

set -euo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:${PATH:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common.sh
source "$SCRIPT_DIR/common.sh"

LOG_FILE="${DATA_PATH}/Logs/daily_restart.log"
RCON_PASS="${RCON_PASSWORD:-${ADMIN_PASSWORD:-}}"
MAX_ATTEMPTS="${RESTART_MAX_ATTEMPTS:-4}"    # 4 intentos por defecto
WAIT_MINUTES="${RESTART_WAIT_MINUTES:-15}"    # 15 minutos entre intentos (ventana total: 1 hora)

log_file() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo -e "$msg"
    echo "$msg" >> "${LOG_FILE}"
    chmod 664 "${LOG_FILE}" 2>/dev/null || true
    chown 1000:1000 "${LOG_FILE}" 2>/dev/null || true
}

get_player_count() {
    if [ -z "${RCON_PASS}" ]; then
        log_file "${YELLOW}[WARN]${NC} RCON_PASSWORD no está definida. Imposible consultar jugadores."
        echo "-1"
        return
    fi

    local output
    output=$(docker exec "${CONTAINER_NAME}" rcon-cli -a "127.0.0.1:${RCON_PORT:-27015}" -p "${RCON_PASS}" "players" 2>&1 || true)

    if [[ "$output" =~ Players\ connected\ \(([0-9]+)\) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        log_file "${YELLOW}[WARN]${NC} Respuesta RCON inesperada: ${output}"
        echo "-1"
    fi
}

mkdir -p "$(dirname "${LOG_FILE}")"
log_file "=================================================="
log_file "Iniciando comprobación de reinicio seguro de PZ..."

if ! is_container_running; then
    log_file "El contenedor ${CONTAINER_NAME} no está corriendo. Iniciando servicio..."
    cd "$PROJECT_ROOT" && $DOCKER_COMPOSE_CMD up -d
    exit 0
fi

if [ -z "${RCON_PASS}" ]; then
    log_file "${RED}[ERROR]${NC} No se configuró RCON_PASSWORD en .env ni ADMIN_PASSWORD."
    exit 1
fi

ATTEMPT=1
while [ "${ATTEMPT}" -le "${MAX_ATTEMPTS}" ]; do
    log_file "Intento ${ATTEMPT}/${MAX_ATTEMPTS}: Consultando jugadores vía RCON..."
    PLAYERS=$(get_player_count)

    if [ "${PLAYERS}" -eq 0 ]; then
        log_file "${GREEN}[OK]${NC} Servidor vacío (0 jugadores). Procediendo a reiniciar de forma segura."

        # 1. Forzar guardado del mundo en memoria a disco
        log_file "Enviando comando 'save' vía RCON..."
        docker exec "${CONTAINER_NAME}" rcon-cli -a "127.0.0.1:${RCON_PORT:-27015}" -p "${RCON_PASS}" "save" || true
        sleep 5

        # 2. Reinicio con Compose (con 60s de gracia para vaciado de DB/chunks)
        log_file "Ejecutando reinicio del contenedor..."
        cd "$PROJECT_ROOT"
        $DOCKER_COMPOSE_CMD restart -t 60 "$CONTAINER_NAME"

        log_file "${GREEN}[EXITO]${NC} Servidor reiniciado correctamente y mundo sincronizado."
        exit 0

    elif [ "${PLAYERS}" -lt 0 ]; then
        log_file "${RED}[ERROR]${NC} Falló la comunicación con RCON (puerto 27015 cerrado o clave incorrecta). Cancelando para evitar interrupciones."
        exit 1
    else
        log_file "${YELLOW}[INFO]${NC} Hay ${PLAYERS} jugador(es) en línea. No se interrumpirá la partida."
        if [ "${ATTEMPT}" -lt "${MAX_ATTEMPTS}" ]; then
            log_file "Esperando ${WAIT_MINUTES} minutos para el siguiente intento..."
            sleep "$((WAIT_MINUTES * 60))"
        fi
    fi

    ATTEMPT=$((ATTEMPT + 1))
done

log_file "${YELLOW}[AVISO]${NC} Se alcanzó el límite de intentos y aún hay jugadores conectados."
log_file "Reinicio pospuesto para el próximo ciclo programado."
exit 0
