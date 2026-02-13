#!/bin/bash

# Obtener directorio del script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cargar Módulos
source "$SCRIPT_DIR/modules/utils.sh"
source "$SCRIPT_DIR/modules/scanner.sh"
source "$SCRIPT_DIR/modules/cracking.sh"
source "$SCRIPT_DIR/modules/attacks/handshake.sh"
source "$SCRIPT_DIR/modules/menus.sh"

# Verificaciones Iniciales
check_root
check_dependencies

# Bucle Principal
while true; do
    banner
    echo ""
    echo -e "${YELLOW}  MENÚ DE ATAQUES${NC}"
    echo ""
    echo -e "  ${CYAN}1${NC}  Ataque WPA/WPA2 clásico (handshake)"
    echo -e "  ${CYAN}2${NC}  Herramientas"
    echo -e "  ${CYAN}3${NC}  Salir"
    echo ""
    read -p "  → Opción: " option
    
    case $option in
        1) capture_handshake ;;
        2) extra_tools_menu ;;
        3) exit 0 ;;
        *) echo -e "${RED}Opción inválida${NC}"; sleep 1 ;;
    esac
done
