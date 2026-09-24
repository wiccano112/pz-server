#!/usr/bin/env bash
# ==============================================================================
# LIST PLAYERS & SAVES INSPECTOR
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

log_header "PARTIDAS GUARDADAS (SAVES MULTIPLAYER)"

SAVES_DIR="$DATA_PATH/Saves/Multiplayer"

if [ -d "$SAVES_DIR" ]; then
    FOUND_SAVES=false
    for save_path in "$SAVES_DIR"/*; do
        if [ -d "$save_path" ]; then
            FOUND_SAVES=true
            SAVE_NAME="$(basename "$save_path")"
            SAVE_SIZE="$(du -sh "$save_path" 2>/dev/null | awk '{print $1}')"
            MOD_DATE="$(date -r "$save_path" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || stat -c '%y' "$save_path" 2>/dev/null | cut -d'.' -f1)"
            
            IS_ACTIVE_CONFIG=""
            if [ "$SAVE_NAME" = "$SERVER_NAME" ]; then
                IS_ACTIVE_CONFIG=" ${GREEN}(Configuración Activa actual)${NC}"
            fi

            echo -e "${BOLD}📁 Partida:${NC} ${CYAN}$SAVE_NAME${NC}$IS_ACTIVE_CONFIG"
            echo -e "   ├─ Tamaño en disco: $SAVE_SIZE"
            echo -e "   ├─ Última modificación: $MOD_DATE"

            # Contar vehículos si existe vehicles.db
            if [ -f "$save_path/vehicles.db" ]; then
                VEHICLES_COUNT=$(python3 -c "
import sqlite3
try:
    c = sqlite3.connect('$save_path/vehicles.db')
    print(c.execute('SELECT COUNT(*) FROM vehicles;').fetchone()[0])
except Exception:
    print('N/A')
" 2>/dev/null || echo "N/A")
                echo -e "   ├─ Vehículos registrados: $VEHICLES_COUNT"
            fi

            # Contar personajes en players.db
            if [ -f "$save_path/players.db" ]; then
                PLAYERS_COUNT=$(python3 -c "
import sqlite3
try:
    c = sqlite3.connect('$save_path/players.db')
    print(c.execute('SELECT COUNT(*) FROM networkPlayers;').fetchone()[0])
except Exception:
    print('N/A')
" 2>/dev/null || echo "N/A")
                echo -e "   └─ Personajes guardados: $PLAYERS_COUNT"
            fi
            echo ""
        fi
    done

    if [ "$FOUND_SAVES" = false ]; then
        log_warn "No se encontraron carpetas de partidas en $SAVES_DIR."
    fi
else
    log_warn "El directorio $SAVES_DIR no existe."
fi

log_header "JUGADORES REGISTRADOS (WHITELIST & ROLES)"

DB_FILE="$DATA_PATH/db/${SERVER_NAME}.db"
if [ -f "$DB_FILE" ]; then
    printf "${BOLD}%-20s %-15s %-25s${NC}\n" "USUARIO" "ROL" "ÚLTIMA CONEXIÓN"
    printf "%-20s %-15s %-25s\n" "--------------------" "---------------" "-------------------------"
    
    python3 -c "
import sqlite3
try:
    conn = sqlite3.connect('$DB_FILE')
    cursor = conn.cursor()
    # Mapeo de roles en PZ Build 42
    roles_map = {0: 'None', 1: 'Banned', 2: 'Player', 4: 'Moderator', 7: 'Admin', 8: 'Overseer'}
    for row in cursor.execute('SELECT username, role, lastConnection FROM whitelist ORDER BY role DESC, username ASC;'):
        uname = row[0]
        role_num = row[1]
        role_name = roles_map.get(role_num, str(role_num))
        last_conn = row[2] if row[2] else 'Nunca'
        print(f'{uname:<20} {role_name:<15} {last_conn:<25}')
except Exception as e:
    print(f'Error al leer base de datos: {e}')
"
    echo ""
else
    log_warn "No se encontró la base de datos de cuentas en $DB_FILE."
fi

log_header "ESTADO DE JUGADORES EN VIVO (ONLINE STATUS)"

if is_container_running; then
    log_info "Servidor en ejecución ($CONTAINER_NAME). Analizando sesiones activas..."
    
    # Buscar el log de usuario más reciente
    LATEST_USER_LOG="$(find "$DATA_PATH/Logs" -name "*_user.txt" -type f -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | awk '{print $2}' || true)"
    
    if [ -n "$LATEST_USER_LOG" ] && [ -f "$LATEST_USER_LOG" ]; then
        python3 -c "
import re, sys

log_file = '$LATEST_USER_LOG'
connected = set()

with open(log_file, 'r', encoding='utf-8', errors='ignore') as f:
    for line in f:
        # Detectar conexiones
        match_conn = re.search(r'\"([^\"]+)\"\s+fully connected', line)
        if match_conn:
            connected.add(match_conn.group(1))
        
        # Detectar desconexiones
        match_disc = re.search(r'\"([^\"]+)\"\s+disconnected player', line)
        if match_disc:
            connected.discard(match_disc.group(1))

if connected:
    print('\033[1;32m● Jugadores conectados actualmente:\033[0m')
    for player in sorted(connected):
        print(f'   • \033[1m{player}\033[0m')
else:
    print('\033[1;33m○ No hay jugadores conectados en este momento.\033[0m')
"
    else
        log_info "No se encontraron logs recientes de conexión para analizar estado en vivo."
    fi
else
    log_warn "El servidor está detenido. No hay jugadores conectados."
fi

log_header "PERSONAJES Y ÚLTIMAS COORDENADAS"

PLAYERS_DB="$DATA_PATH/Saves/Multiplayer/${SERVER_NAME}/players.db"
if [ -f "$PLAYERS_DB" ]; then
    printf "${BOLD}%-18s %-18s %-25s %-10s${NC}\n" "CUENTA" "PERSONAJE" "COORDENADAS (X, Y, Z)" "ESTADO"
    printf "%-18s %-18s %-25s %-10s\n" "------------------" "------------------" "-------------------------" "----------"
    python3 -c "
import sqlite3
try:
    conn = sqlite3.connect('$PLAYERS_DB')
    cursor = conn.cursor()
    for row in cursor.execute('SELECT username, name, x, y, z, isDead FROM networkPlayers ORDER BY username ASC, name ASC;'):
        uname = row[0] if row[0] else 'N/A'
        pname = row[1] if row[1] else uname
        x, y, z = (round(row[2], 1), round(row[3], 1), int(row[4])) if row[2] is not None and row[3] is not None and row[4] is not None else (0, 0, 0)
        coords = f'({x}, {y}, {z})'
        status = '💀 Muerto' if row[5] == 1 else '❤️ Vivo'
        print(f'{uname:<18} {pname:<18} {coords:<25} {status:<10}')
except Exception as e:
    print(f'Error al leer players.db: {e}')
"
    echo ""
else
    log_warn "No se encontró players.db para el mundo $SERVER_NAME."
fi
