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
    
    # Priorizar Hashcat si existe la versión convertida
    local hc22000_file="${cap_file_input%.*}.hc22000"
    
    if [[ "$cap_file_input" == *.hc22000 ]]; then
        # El input ya es el hash
        echo -e "${YELLOW}[*] Modo Hashcat directo...${NC}"
        hashcat -a 0 -m 22000 -w 3 "$cap_file_input" "$wordlist"
    elif [ -f "$hc22000_file" ]; then
        # Se encontró la versión convertida automáticamente
        echo -e "${GREEN}[*] Detectado archivo convertido: $(basename "$hc22000_file")${NC}"
        echo -e "${YELLOW}[*] Usando Hashcat (GPU) para mayor velocidad...${NC}"
        hashcat -a 0 -m 22000 -w 3 "$hc22000_file" "$wordlist"
    else
        # Fallback a CPU solo si no hay opción
        echo -e "${RED}[!] No se encontró archivo .hc22000.${NC}"
        echo -e "${YELLOW}[*] Usando Aircrack-ng (CPU Legacy Mode)...${NC}"
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
    echo -e "${YELLOW}[*] Verificar integridad de archivos (.cap / .hc22000)${NC}"

    # 1. Listar archivos compatibles (.cap y .hc22000)
    # Globbing seguro
    local files=("$WORK_DIR"/*.cap "$WORK_DIR"/*.hc22000)
    local valid_files=()
    
    for f in "${files[@]}"; do
        if [ -e "$f" ]; then
            valid_files+=("$f")
        fi
    done

    if [ ${#valid_files[@]} -eq 0 ]; then
         echo -e "${RED}[!] No se encontraron archivos de captura en $WORK_DIR${NC}"
         read -p "Presiona Enter para volver..."
         return
    fi
    
    echo -e "Archivos disponibles en ${CYAN}$WORK_DIR${NC}:"
    local i=1
    for file in "${valid_files[@]}"; do
        echo -e "  ${CYAN}$i)${NC} $(basename "$file")"
        ((i++))
    done

    echo ""
    read -p "  → Selecciona un archivo (número): " choice

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#valid_files[@]}" ]; then
        echo -e "${RED}[!] Selección inválida.${NC}"
        sleep 1
        return
    fi

    local selected_file="${valid_files[$((choice-1))]}"
    local filename=$(basename "$selected_file")

    echo -e "${YELLOW}[*] Analizando: $filename...${NC}"
    echo ""

    elif [[ "$filename" == *.hc22000 ]]; then
         # Lógica para archivos Hashcat (.hc22000)
         
         if [ ! -s "$selected_file" ]; then
             echo -e "${RED}[FAIL] El archivo .hc22000 está vacío o corrupto.${NC}"
             read -p "Presiona Enter para continuar..."
             return
         fi

         if command -v hcxhashtool &> /dev/null; then
             echo -e "${GREEN}[SUCCESS] Archivo Hashcat válido.${NC}"
             echo -e "${YELLOW}--- Detalles del Hash ---${NC}"
             # Mostrar info útil filtrada
             info=$(hcxhashtool -i "$selected_file" --info=stdout)
             echo "$info" | grep -E "ESSID|BSSID|Encryption|EAPOL"
             echo "---------------------------------------------------"
             echo -e "${CYAN}Total de líneas (hashes): $(wc -l < "$selected_file")${NC}"
         else
             # Fallback manual
             line_count=$(wc -l < "$selected_file")
             echo -e "${GREEN}[SUCCESS] Archivo válido (texto no vacío).${NC}"
             echo -e "Contiene ${CYAN}$line_count${NC} hashes listos para crackear."
         fi
         
    elif [[ "$filename" == *.cap ]]; then
         # Lógica Aircrack para .cap
         aircrack_output=$(aircrack-ng "$selected_file" 2>&1)
         
         # Filtrar líneas con handshakes > 0
         valid_handshakes=$(echo "$aircrack_output" | grep -E "\([1-9][0-9]* handshake\)")
         
         if [ -n "$valid_handshakes" ]; then
             echo -e "${GREEN}[SUCCESS] ¡Se detectaron Handshakes Válidos!${NC}"
             echo -e "${CYAN}Redes confirmadas:${NC}"
             echo "$valid_handshakes"
             
             # Ofrecer conversión si no existe el .hc22000
             hc_file="${selected_file%.*}.hc22000"
             if [ ! -f "$hc_file" ] && command -v hcxpcapngtool &> /dev/null; then
                 echo ""
                 read -p "¿Deseas generar el archivo Hashcat (.hc22000) ahora? (S/n): " conv
                 conv=${conv:-S}
                 if [[ "$conv" =~ ^[sS] ]]; then
                     hcxpcapngtool -o "$hc_file" "$selected_file" >/dev/null 2>&1
                     if [ -f "$hc_file" ]; then
                         echo -e "${GREEN}[+] Archivo generado: $(basename "$hc_file")${NC}"
                     else
                         echo -e "${RED}[!] Error al convertir.${NC}"
                     fi
                 fi
             fi
         else
             echo -e "${RED}[FAIL] El archivo no contiene handshakes válidos.${NC}"
             echo "Resumen:"
             echo "$aircrack_output" | grep -E "handshake|Encryption" | head -n 5
         fi
    fi

    echo ""
    read -p "Presiona Enter para continuar..."
}

function crack_password() {
    banner
    echo -e "${YELLOW}[*] Ataque de Diccionario (Hashcat Mode)${NC}"
    echo -e "${CYAN}[i] Nota: Hashcat requiere archivos convertidos (.hc22000).${NC}"
    echo -e "${CYAN}    Si tu captura es .cap, asegúrate de que se haya convertido automáticamente.${NC}"
    
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

    # 2. Pedir archivo de hash (.hc22000)
    # Cambio solicitado: Filtrar solo .hc22000
    if ! select_file "*.hc22000" "Selecciona el archivo Hashcat (.hc22000):"; then
        echo -e "${YELLOW}[INFO] No se encontraron archivos .hc22000.${NC}"
        echo -e "${YELLOW}       Si tienes un .cap, usa la opción de 'Herramientas > Convertir' o captura de nuevo.${NC}"
        read -p "Presiona Enter para volver..."
        return
    fi
    hash_file="$SELECTED_FILE"

    # 3. Ejecutar Hashcat
    echo -e "${YELLOW}[*] Iniciando ataque con Hashcat (Mode 22000)...${NC}"
    echo -e "${CYAN}Comando: hashcat -a 0 -m 22000 -w 3 [archivo] [diccionario]${NC}"
    
    # Auto-detectar dispositivo (Hashcat lo hace solo, pero -w 3 ayuda a rendimiento)
    hashcat -a 0 -m 22000 -w 3 "$hash_file" "$wordlist"
    
    echo ""
    echo -e "${YELLOW}[*] Ataque finalizado.${NC}"
    
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
