#!/bin/bash

# ==============================================================================
# MENUS MODULE
# ==============================================================================

function extra_tools_menu() {
    clear
    banner
    echo -e "${YELLOW}╔══════════════════ EXTRA TOOLS ═══════════════════╗${NC}"
    printf "${YELLOW}║${NC} %-48s ${YELLOW}║${NC}\n" " 1) Escanear Redes (airodump-ng)"
    printf "${YELLOW}║${NC} %-48s ${YELLOW}║${NC}\n" " 2) Ataque Desautenticación Manual"
    printf "${YELLOW}║${NC} %-48s ${YELLOW}║${NC}\n" " 3) Verificar Handshake (.cap)"
    printf "${YELLOW}║${NC} %-48s ${YELLOW}║${NC}\n" " 4) Crackear Contraseña (Manual)"
    echo -e "${YELLOW}╠══════════════════════════════════════════════════╣${NC}"
    printf "${YELLOW}║${NC} %-48s ${YELLOW}║${NC}\n" " 5) Volver"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    read -p "Opción: " ext_opt
    case $ext_opt in
        1) scan_networks ;;
        2) deauth_attack ;;
        3) verify_handshake ;;
        4) crack_password ;;
        5) return ;;
    esac
}
