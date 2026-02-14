#!/bin/bash

function extra_tools_menu() {
    clear
    banner
    echo ""
    echo -e "${YELLOW}  HERRAMIENTAS${NC}"
    echo ""
    echo -e "  ${CYAN}1${NC}  Verificar capturas y handshakes"
    echo -e "  ${CYAN}2${NC}  Crackear contraseña (manual)"
    echo -e "  ${CYAN}3${NC}  Volver"
    echo ""
    read -p "  → Opción: " ext_opt
    case $ext_opt in
        1) verify_handshake ;;
        2) crack_password ;;
        3) return ;;
        *) echo "Opción inválida" ;;
    esac
}
