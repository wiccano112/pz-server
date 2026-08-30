# CPU OPTIMIZATION & CO-OP GAMING RUNBOOK

Este documento detalla la estrategia de asignación de núcleos (CPU Pinning / Affinity) para hospedar el servidor dedicado y jugar al cliente de Project Zomboid simultáneamente en una arquitectura híbrida (Intel 13th Gen / P-Cores + E-Cores).

---

## 1. PERFIL DE HARDWARE DEL SISTEMA

- **CPU**: Intel Core i7-13800H (14 núcleos / 20 hilos)
- **Topología**:
  - **P-Cores (Rendimiento)**: Hilos `0 - 11` (6 núcleos físicos con Hyper-Threading, hasta **5.20 GHz** con máxima memoria caché).
  - **E-Cores (Eficiencia)**: Hilos `12 - 19` (8 núcleos físicos monohilo, hasta **4.00 GHz** para servicios de fondo).

---

## 2. PERFILES DE CONFIGURACIÓN

### 🟢 Perfil 1: Dedicación Total de P-Cores al Servidor (ACTUAL)
Diseñado para máximo rendimiento del servidor cuando el host no está jugando o para partidas con muchos jugadores/mods pesados.

| Componente | Afinidad CPU | Rango de Hilos | Tipo de Núcleo |
| :--- | :--- | :--- | :--- |
| **`pz-server` (Docker)** | `cpuset: "0-11"` | `0 a 11` | ⚡ Todos los P-Cores (5.2 GHz) |
| **`pz-panel` (Docker)** | `cpuset: "12-19"` | `12 a 19` | 🍃 Todos los E-Cores (4.0 GHz) |
| **Cliente / Sistema / Apps** | Automático (CFS) | `0 a 19` | Balanceado por el kernel |

---

### 🔵 Perfil 2: Aislamiento para "Host & Play" (Recomendado si juegas en el mismo equipo)
Diseñado para evitar cualquier competencia por caché o ciclos de reloj entre el servidor dedicado y el cliente de juego.

```
┌─────────────────────────────────────────────────────────────┐
│ ⚡ P-Cores (0 a 5)   ──> Servidor Dedicado (pz-server)      │
│ ⚡ P-Cores (6 a 11)  ──> Cliente de Juego (Steam PZ)        │
│ 🍃 E-Cores (12 a 19) ──> PZ-Panel + Discord + Steam + SO    │
└─────────────────────────────────────────────────────────────┘
```

#### Ventajas del Perfil 2:
1. **FPS y Frametime 100% estables**: El cliente del juego tiene 6 hilos P de 5.2 GHz exclusivos; ninguna tarea pesada del servidor (como compresión de backups o generación de zombis lejanos) interferirá con el hilo de renderizado del cliente.
2. **Menores temperaturas y menor consumo**: Al no saturar todos los P-cores con ambos procesos, el disipador térmico mantiene frecuencias Boost más sostenidas.
3. **Cero stuttering**: No hay micro-parones al conducir rápido o en hordas.

---

## 3. CÓMO CAMBIAR AL PERFIL 2 (PASO A PASO)

### Paso 1: Modificar `docker-compose.yml` en `pz-server`
1. Detén el servidor:
   ```bash
   docker compose down
   ```
2. Edita `docker-compose.yml` y cambia `cpuset: "0-11"` por `cpuset: "0-5"`:
   ```yaml
   services:
     pz-server:
       image: indifferentbroccoli/projectzomboid-server-docker:latest
       container_name: ${CONTAINER_NAME}
       restart: unless-stopped
       cpuset: "0-5"  # 👈 3 P-Cores / 6 hilos dedicados al servidor
   ```
3. Inicia el servidor:
   ```bash
   docker compose up -d
   ```

### Paso 2: Configurar Parámetros de Lanzamiento en Steam para tu Juego
1. Abre **Steam**.
2. Haz clic derecho en **Project Zomboid** -> **Propiedades...**
3. En la pestaña **General**, localiza **Parámetros de lanzamiento** (*Launch Options*).
4. Introduce exactamente el siguiente comando:
   ```bash
   taskset -c 6-11 %command%
   ```
5. Cierra la ventana y abre tu juego normalmente.

---

## 4. MONITORIZACIÓN Y VERIFICACIÓN EN VIVO

Para verificar que la carga se reparte exactamente en los núcleos asignados mientras juegas:

```bash
# 1. Monitorear uso de CPU por hilo en tiempo real
htop
# (Presiona F2 -> Display options -> Activa 'Detailed CPU time' y observa CPUs 0-5 vs 6-11 vs 12-19)

# 2. Inspeccionar la asignación del contenedor Docker
docker inspect pz-server --format '{{.HostConfig.CpusetCpus}}'
docker inspect pz-panel --format '{{.HostConfig.CpusetCpus}}'
```
