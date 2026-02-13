#!/bin/bash

function show_target_selection_menu() {
    local source_file="$1"
    
    echo ""
    echo -e "${YELLOW}  REDES DISPONIBLES${NC}"
    echo ""
    printf "  ${CYAN}%-2s  %-17s  %-2s  %-7s  %-8s  %-28s${NC}\n" "ID" "BSSID" "CH" "PWR" "SEC" "ESSID"
    printf "  ${CYAN}%-2s  %-17s  %-2s  %-7s  %-8s  %-28s${NC}\n" "--" "-----------------" "--" "-------" "--------" "----------------------------"
    
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
             
             printf "  %-2s  ${CYAN}%-17s${NC}  %-2s  ${pwr_color}%-7s${NC}  %-8s  ${GREEN}%-28.28s${NC}\n" "$i" "$bssid" "$channel" "$pwr" "$security" "$essid"
             ((i++))
        fi
    done < "$source_file"
    
    echo ""
    echo -e "  ${CYAN}0${NC}  Entrada manual o re-escanear"
    echo ""
    read -p "  → Selecciona el número: " selection
    
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
    
    airodump-ng --output-format csv -w "$tmp_scan_prefix" "$mon_interface" > /dev/null 2>&1 &
    local pid=$!

    for ((i=1; i<=duration; i++)); do
        echo -n "▓"
        sleep 1
    done
    echo ""
    
    kill $pid 2>/dev/null
    wait $pid 2>/dev/null
    
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
        
        # Filtros: Ocultas y Open (OPN)
        if(length(essid)>0 && essid!="<Oculta>" && priv!="OPEN" && priv!="OPN") {
           if(length(bssid)==17) print bssid "|" chan "|" essid "|" pwr "|" priv
        }
    }' "$csv_file" | sort -t'|' -k4 -nr > "$formatted_list"
    
    if [ -s "$formatted_list" ]; then
        show_target_selection_menu "$formatted_list"
        return $?
    else
        echo -e "${RED}[!] No se encontraron redes.${NC}"
        return 1
    fi
}


