#!/bin/bash

function extra_tools_menu() {
    clear
    banner
    echo ""
    echo -e "${YELLOW}  HERRAMIENTAS${NC}"
    echo ""
    echo -e "  ${CYAN}1${NC}  Escanear redes (airodump-ng)"
    echo -e "  ${CYAN}2${NC}  Ataque desautenticación manual"
    echo -e "  ${CYAN}3${NC}  Verificar handshake (.cap)"
    echo -e "  ${CYAN}4${NC}  Crackear contraseña (manual)"
    echo -e "  ${CYAN}5${NC}  Convertir .cap a .hc22000 (hashcat)"
    echo ""
    echo -e "  ${CYAN}6${NC}  Volver"
    echo ""
    read -p "  → Opción: " ext_opt
    case $ext_opt in
        1) scan_networks ;;
        2) deauth_attack ;;
        3) verify_handshake ;;
        4) crack_password ;;
        5) convert_cap_to_hc22000 ;;
        6) return ;;
    esac
}
