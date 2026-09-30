#!/usr/bin/env bash
# ==============================================================================
# UPGRADE PRODUCTION SERVER TO BUILD 42.21 UNSTABLE
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

FORCE=false
SKIP_BACKUP=false

show_help() {
    cat << EOF
Uso: $(basename "$0") [OPCIONES]

Actualiza de forma segura el servidor de producción a Build 42.21 Unstable.
Incluye verificación de jugadores activos, guardado forzado del mundo,
creación automática de snapshot preventivo y monitoreo del arranque.

Opciones:
  -y, --yes             Confirmación automática (omite preguntas interactivas).
  --skip-backup         Omite la creación del snapshot (NO recomendado).
  -h, --help            Muestra esta ayuda.

Ejemplo:
  $(basename "$0")
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes)
            FORCE=true
            shift
            ;;
        --skip-backup)
            SKIP_BACKUP=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "Opción no reconocida: $1"
            show_help
            exit 1
            ;;
    esac
done

log_header "ACTUALIZACIÓN A PROJECT ZOMBOID 42.21 (PRODUCCIÓN)"

# 1. Comprobar estado actual del contenedor y jugadores
if is_container_running; then
    log_info "Comprobando jugadores conectados en $CONTAINER_NAME..."
    PLAYER_LIST=$(docker exec "$CONTAINER_NAME" rcon-cli -c /home/steam/server/rcon.yml players 2>/dev/null || true)
    
    CONNECTED_COUNT=0
    if [[ "$PLAYER_LIST" =~ \(([0-9]+)\) ]]; then
        CONNECTED_COUNT="${BASH_REMATCH[1]}"
    fi

    if [ "$CONNECTED_COUNT" -gt 0 ]; then
        log_warn "¡ATENCIÓN! Hay $CONNECTED_COUNT jugador(es) conectado(s) actualmente:"
        echo "$PLAYER_LIST"
        echo ""
        if [ "$FORCE" = false ]; then
            read -rp "¿Deseas enviar un mensaje de advertencia in-game a los jugadores antes de apagar? (S/n): " SEND_MSG
            if [[ ! "$SEND_MSG" =~ ^[nN]$ ]]; then
                read -rp "Minutos de aviso para el mantenimiento [por defecto: 2]: " MSG_MINS
                MSG_MINS="${MSG_MINS:-2}"
                docker exec "$CONTAINER_NAME" rcon-cli -c /home/steam/server/rcon.yml \
                    "servermsg \"ATENCION: El servidor se actualizara a la version 42.21 en $MSG_MINS minutos. Por favor desconectate en un lugar seguro.\"" || true
                log_info "Aviso transmitido in-game. Esperando 10 segundos..."
                sleep 10
            fi

            read -rp "¿Confirmas detener el servidor e iniciar la migración ahora? (s/N): " CONFIRM_UPGRADE
            if [[ ! "$CONFIRM_UPGRADE" =~ ^[sSyY]$ ]]; then
                log_info "Actualización cancelada por el usuario."
                exit 0
            fi
        fi
    else
        log_info "No hay jugadores conectados actualmente."
    fi

    # 2. Guardar partida mediante RCON antes de bajar el contenedor
    log_info "Ejecutando guardado forzado del mundo (RCON save)..."
    docker exec "$CONTAINER_NAME" rcon-cli -c /home/steam/server/rcon.yml save 2>/dev/null || true
    
    # 3. Detener contenedor de forma segura
    log_info "Deteniendo contenedor $CONTAINER_NAME (descargando chunks de memoria)..."
    cd "$PROJECT_ROOT"
    $DOCKER_COMPOSE_CMD down
    log_success "Servidor detenido correctamente."
else
    log_info "El contenedor de producción ($CONTAINER_NAME) ya se encuentra detenido."
fi

# 4. Crear Snapshot Preventivo Completo en v42.20
BACKUP_DIR="$DATA_PATH/backups"
mkdir -p "$BACKUP_DIR"

if [ "$SKIP_BACKUP" = false ]; then
    TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
    SNAPSHOT_FILE="$BACKUP_DIR/snapshot_pre_42_21_${TIMESTAMP}.tar.gz"
    
    log_info "Generando snapshot preventivo de seguridad..."
    log_info "Destino: $SNAPSHOT_FILE"
    
    cd "$DATA_PATH"
    TARGETS=()
    [ -d "Saves" ] && TARGETS+=("Saves")
    [ -d "Server" ] && TARGETS+=("Server")
    [ -d "db" ] && TARGETS+=("db")
    [ -f "options.ini" ] && TARGETS+=("options.ini")
    [ -d "mods" ] && TARGETS+=("mods")

    if [ ${#TARGETS[@]} -eq 0 ]; then
        log_error "No se encontraron carpetas esenciales en $DATA_PATH para respaldar."
        exit 1
    fi

    tar -czf "$SNAPSHOT_FILE" "${TARGETS[@]}"
    
    # Guardar referencia al último snapshot previo
    echo "$SNAPSHOT_FILE" > "$BACKUP_DIR/.last_pre_upgrade_snapshot"
    
    SNAPSHOT_SIZE="$(du -h "$SNAPSHOT_FILE" | awk '{print $1}')"
    log_success "Snapshot preventivo generado con éxito ($SNAPSHOT_SIZE): $(basename "$SNAPSHOT_FILE")"
else
    log_warn "Omitiendo creación de snapshot (--skip-backup activado)."
fi

# 5. Configurar rama unstable en .env
log_info "Actualizando .env con SERVER_BRANCH=unstable..."
if grep -q "^SERVER_BRANCH=" "$PROJECT_ROOT/.env"; then
    sed -i 's/^SERVER_BRANCH=.*/SERVER_BRANCH=unstable/' "$PROJECT_ROOT/.env"
else
    echo "SERVER_BRANCH=unstable" >> "$PROJECT_ROOT/.env"
fi

# Asegurar permisos en data/
chown -R "$PUID:$PGID" "$DATA_PATH" 2>/dev/null || chmod -R 775 "$DATA_PATH" || true
chmod -R 775 "$DATA_PATH" 2>/dev/null || true

# 6. Levantar servidor en Build 42.21
log_info "Iniciando servidor en segundo plano con la nueva versión..."
cd "$PROJECT_ROOT"
$DOCKER_COMPOSE_CMD up -d

log_success "Contenedor $CONTAINER_NAME iniciado."
echo ""
echo -e "${YELLOW}ℹ️  El servidor está descargando la Build 42.21 Unstable mediante DepotDownloader.${NC}"
echo -e "${YELLOW}   Posteriormente descargará las actualizaciones de los 13 mods e iniciará el juego.${NC}"
echo ""
echo -e "Comandos útiles de seguimiento:"
echo -e "  Ver logs en vivo:            ${BOLD}docker compose logs -f${NC}"
echo -e "  Verificar versión iniciada:  ${BOLD}grep -i \"version=\" data/server-console.txt | tail -n 5${NC}"
echo -e "  Rollback si algo falla:      ${BOLD}./scripts/rollback_to_42_20.sh${NC}"
echo ""

if [ "$FORCE" = false ]; then
    read -rp "¿Deseas seguir los logs en vivo ahora? (S/n): " FOLLOW_LOGS
    if [[ ! "$FOLLOW_LOGS" =~ ^[nN]$ ]]; then
        $DOCKER_COMPOSE_CMD logs -f
    fi
fi
