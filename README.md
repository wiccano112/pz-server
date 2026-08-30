# Servidor Dedicado de Project Zomboid (Docker)

Este proyecto permite levantar y administrar de manera sencilla un servidor dedicado de **Project Zomboid** utilizando Docker y Docker Compose.

---

## 📋 Requisitos Previos

- Tener instalado **Docker** y **Docker Compose**.
- Al menos **8 GB de RAM** disponibles en el sistema (recomendado 16 GB si usas muchos mods).
- Puertos abiertos en tu router/firewall:
  - `16261/UDP` (Puerto principal del juego)
  - `16262/UDP` (Puerto de conexión directa de clientes)
  - `27015/TCP` (Steam Query / RCON)

---

## 🚀 Inicio Rápido

1. **Configurar variables de entorno:**
   ```bash
   cp .env.example .env
   # Edita .env con tus valores personalizados (contraseña de admin, RAM, etc.)
   ```

2. **Iniciar el servidor:**
   ```bash
   docker compose up -d
   ```

3. **Ver los logs en tiempo real:**
   ```bash
   docker compose logs -f
   ```

4. **Detener el servidor:**
   ```bash
   docker compose down
   ```

---

## 🖥️ Panel Web de Administración (PZ-Panel)

Para administrar el servidor gráficamente desde el navegador, existe el proyecto complementario **[PZ-Panel](https://github.com/wiccano112/pz-panel)** (`../pz-panel`):

- **Dashboard en Vivo:** Monitorización de CPU, RAM, Uptime y streaming de logs con Server-Sent Events (SSE).
- **Gestor de Mods:** Catálogo de Steam Workshop (Build 42) y reordenamiento interactivo del orden de carga / mapas.
- **Editor de Sandbox:** Modificación visual y segura de `<SERVER_NAME>_SandboxVars.lua`.
- **Moderación:** Lista blanca (Whitelist), baneos por IP/SteamID y emisión de mensajes globales (Broadcast).

### Cómo iniciar PZ-Panel:
```bash
cd ../pz-panel
pnpm install
pnpm dev
```
Luego abre tu navegador en `http://localhost:3000`.

---

## ⚙️ Configuración Básica

### 1. Variables de Entorno (`.env`)
Puedes editar el archivo `.env` para ajustar:
- `CONTAINER_NAME`: Nombre del contenedor Docker (ejemplo: `pz-server`).
- `SERVER_NAME`: Nombre interno de la configuración y mundo (ejemplo: `pzserver`).
- `ADMIN_PASSWORD`: Contraseña del usuario administrador `admin`.
- `MAX_RAM`: Memoria máxima asignada al servidor (ejemplo: `8G`, `12G`, `16G`).
- `PUID` / `PGID`: UID y GID del usuario host (por defecto: `1000`).
- `GAME_PORT`, `DIRECT_PORT`, `RCON_PORT`: Puertos de red del servidor.
- `DATA_PATH`: Ruta en el host donde se almacenan los datos del servidor (por defecto: `./data`).

### 2. Configuración del Juego (`data/Server/`)
- **`data/Server/<SERVER_NAME>.ini`**: Ajustes de red, contraseñas de acceso, bienvenida, PVP, y lista de Mods / Workshop Items.
- **`data/Server/<SERVER_NAME>_SandboxVars.lua`**: Parámetros de la partida (velocidad de zombis, transmisión del virus, cantidad de loot, tiempo, etc.).
- **`data/Server/<SERVER_NAME>_spawnregions.lua`**: Regiones de aparición de jugadores.

> ⚠️ **Importante:** Antes de editar archivos `.ini` o `.lua` manualmente en `data/Server/`, detén el servidor (`docker compose down`). Si usas PZ-Panel, este gestiona los guardados automáticamente.

---

## 🧩 Gestión de Mods

Para agregar mods manualmente al servidor, edita `data/Server/<SERVER_NAME>.ini`:

1. Añade los IDs de Steam Workshop en `WorkshopItems`:
   ```ini
   WorkshopItems=2196102849;2503622437;2896041179;3077900375
   ```
2. Añade los identificadores de mod en `Mods`:
   ```ini
   Mods=errorMagnifier;ChuckleberryFinnAlertSystem;SkillRecoveryJournal;RavenCreek
   ```
3. Si el mod incluye mapas (como *Raven Creek*), agrégalo al inicio de la variable `Map`:
   ```ini
   Map=RavenCreek;Muldraugh, KY
   ```

*(También puedes gestionar tus mods con 1 clic desde PZ-Panel en `http://localhost:3000/mods`)*.

---

## 🎮 Cómo Conectarse

1. Abre **Project Zomboid**.
2. Ve a **Unirse (Join)** -> **Internet** o **Favoritos**.
3. Añade la IP de tu servidor y los siguientes datos:
   - **Puerto:** `16261`
   - **Nombre de usuario:** Tu nombre elegido.
   - **Contraseña de cuenta:** La contraseña de tu cuenta personal en el servidor.
   - **Contraseña del servidor:** (Vacía si el servidor es público/sin clave general).

---

## 🛠️ Comandos Útiles

| Acción | Comando |
| :--- | :--- |
| **Iniciar servidor** | `docker compose up -d` |
| **Detener servidor de forma segura** | `docker compose down` |
| **Reiniciar servidor** | `docker compose restart` |
| **Monitorear logs** | `docker compose logs -f pz-server` |
| **Ver estado del contenedor** | `docker compose ps` |
| **Acceder a la consola interactiva** | `docker attach pz-server` (Ctrl+P, Ctrl+Q para salir sin detener) |
