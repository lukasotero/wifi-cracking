#!/bin/bash

# ==============================================================================
# CRACKING: PASSWORD CRACKING & VERIFICATION
# ==============================================================================

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

function verify_handshake() {
    banner
    echo -e "${YELLOW}[*] Verificar integridad del Handshake${NC}"
    
    while true; do
        read -p "Ingresa la ruta del archivo .cap: " cap_file
        if [ -f "$cap_file" ]; then break; else echo -e "${RED}[!] Archivo no encontrado.${NC}"; fi
    done
    
    read -p "Ingresa el BSSID (opcional, Enter para omitir): " bssid
    
    echo -e "${YELLOW}[*] Analizando archivo con cowpatty...${NC}"
    
    if [ -z "$bssid" ]; then
        cowpatty -c -r "$cap_file"
    else
        echo -e "${YELLOW}[*] Usando aircrack-ng para validar handshake de $bssid...${NC}"
        output=$(aircrack-ng -b "$bssid" "$cap_file" 2>&1)
        if echo "$output" | grep -q "1 handshake"; then
             echo -e "${GREEN}[OK] Handshake VÁLIDO encontrado para $bssid.${NC}"
        else
             echo -e "${RED}[!] NO se detectó un handshake válido o completo.${NC}"
             echo "Salida de aircrack-ng:"
             echo "$output" | grep -E "handshake|No valid packets"
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
    while true; do
        read -p "Ingresa la ruta del archivo de captura (.cap): " cap_file
        if [ -f "$cap_file" ]; then
            break
        else
            echo -e "${RED}[!] El archivo no existe. Intenta de nuevo.${NC}"
        fi
    done

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
