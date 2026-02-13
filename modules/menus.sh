#!/bin/bash

function extra_tools_menu() {
    clear
    banner
    echo ""
    echo -e "${YELLOW}  HERRAMIENTAS${NC}"
    echo ""
    echo -e "  ${CYAN}1${NC}  Verificar handshake (.cap)"
    echo -e "  ${CYAN}2${NC}  Crackear contraseña (manual)"
    echo -e "  ${CYAN}3${NC}  Convertir .cap a .hc22000 (hashcat)"
    echo ""
    echo -e "  ${CYAN}4${NC}  Volver"
    echo ""
    read -p "  → Opción: " ext_opt
    case $ext_opt in
        1) verify_handshake ;;
        2) crack_password ;;
        3) convert_cap_to_hc22000 ;;
        4) return ;;
    esac
}
