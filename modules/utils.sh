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
    echo "  │  WiFi Cracking Automation Toolkit                  │"
    echo "  │  Dev by: Lukas Otero                               │"
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
echo -e "${CYAN}  │${NC}  ${GREEN}●${NC} Captura de Handshake en Progreso               ${CYAN}│${NC}"
echo -e "${CYAN}  ╰─────────────────────────────────────────────────────╯${NC}"
echo ""
echo -e "  ${YELLOW}Target:${NC} $BSSID"
echo ""
echo -e "  ${CYAN}ℹ${NC}  Esta ventana se cerrará automáticamente al capturar"
echo -e "  ${CYAN}ℹ${NC}  Ejecuta ataques deauth desde el menú principal"
echo -e "  ${CYAN}ℹ${NC}  Si no se captura, el programa NO está trabado"
echo ""
echo -e "${YELLOW}[*]${NC} Iniciando airodump-ng..."
echo ""

# Ejecutar airodump en background
eval "$CMD" &
AIRODUMP_PID=$!

# Función para verificar handshake
check_handshake() {
    local cap_file=""
    
    # Buscar archivo de captura
    if [ -f "${CAP_PATH}-01.cap" ]; then
        cap_file="${CAP_PATH}-01.cap"
    elif [ -f "${CAP_PATH}.cap" ]; then
        cap_file="${CAP_PATH}.cap"
    fi
    
    if [ ! -z "$cap_file" ] && [ -f "$cap_file" ]; then
        if aircrack-ng -b "$BSSID" "$cap_file" 2>&1 | grep -q "1 handshake"; then
            return 0
        fi
    fi
    return 1
}

# Monitoreo continuo
echo -e "${CYAN}[*] Monitoreando captura... (verificando cada 3 segundos)${NC}"
COUNTER=0

while kill -0 $AIRODUMP_PID 2>/dev/null; do
    sleep 3
    COUNTER=$((COUNTER + 1))
    
    # Mostrar indicador de actividad cada 3 segundos
    echo -ne "${YELLOW}[$(date +%H:%M:%S)]${NC} Verificando handshake... (intento #$COUNTER)\r"
    
    if check_handshake; then
        echo ""
        echo ""
        echo -e "${GREEN}  ╭─────────────────────────────────────────────────────╮${NC}"
        echo -e "${GREEN}  │${NC}  ${GREEN}✓${NC} Handshake Capturado Exitosamente                ${GREEN}│${NC}"
        echo -e "${GREEN}  ╰─────────────────────────────────────────────────────╯${NC}"
        echo ""
        echo -e "${YELLOW}[*]${NC} Deteniendo captura..."
        
        # Matar proceso de airodump
        kill $AIRODUMP_PID 2>/dev/null
        wait $AIRODUMP_PID 2>/dev/null
        
        echo -e "${GREEN}[+]${NC} Proceso finalizado correctamente"
        echo -e "${CYAN}[*]${NC} Esta ventana se cerrará en 3 segundos..."
        sleep 3
        exit 0
    fi
done

# Si el proceso terminó sin capturar handshake
echo ""
echo -e "${RED}[!] El proceso de captura finalizó.${NC}"
echo -e "${YELLOW}[*] Esta ventana se cerrará en 5 segundos...${NC}"
sleep 5
WRAPPER_EOF

    chmod +x "$wrapper_script"
    
    # Construir comando completo con el wrapper
    local full_cmd="$wrapper_script '$cmd' '$bssid' '$cap_path'"
    
    # Intentar detectar emuladores de terminal comunes en Kali/Linux
    if command -v x-terminal-emulator > /dev/null 2>&1; then
        x-terminal-emulator -e "bash -c '$full_cmd'" &
    elif command -v qterminal > /dev/null 2>&1; then
        qterminal -e "bash -c '$full_cmd'" &
    elif command -v gnome-terminal > /dev/null 2>&1; then
        gnome-terminal -- bash -c "$full_cmd" &
    elif command -v xfce4-terminal > /dev/null 2>&1; then
        xfce4-terminal -e "bash -c '$full_cmd'" &
    elif command -v xterm > /dev/null 2>&1; then
        xterm -title "$title" -e "bash -c '$full_cmd'" &
    else
        echo -e "${RED}[!] No se pudo abrir una nueva terminal automáticamente.${NC}"
        echo -e "${YELLOW}[*] Ejecutando en segundo plano (background)...${NC}"
        eval "$cmd" &
    fi
    
    # Limpiar script wrapper después de 2 segundos (dar tiempo a que se ejecute)
    (sleep 2; rm -f "$wrapper_script" 2>/dev/null) &
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




