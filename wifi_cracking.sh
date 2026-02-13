#!/bin/bash

# ==============================================================================
# WIFI CRACKING AUTOMATION TOOLKIT
# ==============================================================================
# MAIN SCRIPT
# ==============================================================================
# Description:
#   Main entry point that loads all modules and runs the primary interactive loop.
# ==============================================================================

# 1. Obtener directorio del script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 2. Cargar Módulos (Sourcing)
#    Orden de carga importante para dependencias internas
source "$SCRIPT_DIR/modules/utils.sh"
source "$SCRIPT_DIR/modules/scanner.sh"
source "$SCRIPT_DIR/modules/cracking.sh"
source "$SCRIPT_DIR/modules/attacks/handshake.sh"
source "$SCRIPT_DIR/modules/attacks/deauth.sh"
source "$SCRIPT_DIR/modules/attacks/wps.sh"
source "$SCRIPT_DIR/modules/attacks/pmkid.sh"
source "$SCRIPT_DIR/modules/menus.sh"

# 3. Verificaciones Iniciales
check_root
check_dependencies

# 4. Bucle Principal del Programa
while true; do
    banner
    echo -e "${YELLOW}╔══════════════════ ATTACK MENU ═══════════════════╗${NC}"
    printf "${YELLOW}║${NC} %-48s ${YELLOW}║${NC}\n" " 1) Ataque WPA/WPA2 Clásico (Handshake)"
    printf "${YELLOW}║${NC} %-48s ${YELLOW}║${NC}\n" " 2) Ataque WPS (Pixie Dust)"
    printf "${YELLOW}║${NC} %-48s ${YELLOW}║${NC}\n" " 3) Ataque PMKID (Client-less)"
    echo -e "${YELLOW}╠══════════════════════════════════════════════════╣${NC}"
    printf "${YELLOW}║${NC} %-48s ${YELLOW}║${NC}\n" " 4) Herramientas Extra (Crackear, Tests)"
    printf "${YELLOW}║${NC} %-48s ${YELLOW}║${NC}\n" " 5) Detener Modo Monitor y Salir"
    printf "${YELLOW}║${NC} %-48s ${YELLOW}║${NC}\n" " 6) Salir"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    read -p "Selecciona una opción: " option
    
    case $option in
        1) capture_handshake ;;
        2) wps_attack ;;
        3) pmkid_attack ;;
        4) extra_tools_menu ;;
        5) exit 0 ;; # El trap manejará la detención
        6) exit 0 ;;
        *) echo -e "${RED}Opción inválida${NC}"; sleep 1 ;;
    esac
done
