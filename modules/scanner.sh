#!/bin/bash

function show_target_selection_menu() {
    local source_file="$1"
    
    echo -e "\n${YELLOW}╔════╤═══════════════════╤════╤═════════╤══════════╤══════════════════════════════╗${NC}"
    printf "${YELLOW}║${NC} %-2s ${YELLOW}│${NC} %-17s ${YELLOW}│${NC} %-2s ${YELLOW}│${NC} %-7s ${YELLOW}│${NC} %-8s ${YELLOW}│${NC} %-28s ${YELLOW}║${NC}\n" "ID" "BSSID" "CH" "PWR" "SEC" "ESSID"
    echo -e "${YELLOW}╠════╪═══════════════════╪════╪═════════╪══════════╪══════════════════════════════╣${NC}"
    
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
             
             printf "${YELLOW}║${NC} %-2s ${YELLOW}│${NC} %-17s ${YELLOW}│${NC} %-2s ${YELLOW}│${NC} ${pwr_color}%-7s${NC} ${YELLOW}│${NC} %-8s ${YELLOW}│${NC} %-28.28s ${YELLOW}║${NC}\n" "$i" "$bssid" "$channel" "$pwr" "$security" "$essid"
             ((i++))
        fi
    done < "$source_file"
    
    echo -e "${YELLOW}╚════╧═══════════════════╧════╧═════════╧══════════╧══════════════════════════════╝${NC}"
    
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
            
            # Filtros: Ocultas y Open
            if(length(essid)>0 && essid!="<Oculta>" && priv!="OPEN") {
               if(length(bssid)==17) print bssid "|" chan "|" essid "|" pwr "|" priv
            }
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

function scan_networks() {
    banner
    ensure_mon_interface
    echo -e "${YELLOW}[*] Iniciando escaneo de redes (Modo Monitor).${NC}"
    echo -e "${YELLOW}[*] Presiona CTRL+C para detener y volver al menú.${NC}"
    read -p "Presiona Enter para comenzar..."
    airodump-ng "$mon_interface"
}
