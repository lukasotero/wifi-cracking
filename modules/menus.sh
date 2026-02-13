#!/bin/bash

function extra_tools_menu() {
    clear
    banner
    echo -e "${YELLOW}╔══════════════════ EXTRA TOOLS ═══════════════════╗${NC}"
    printf "${YELLOW}║${NC} %-48s ${YELLOW}║${NC}\n" " 1) Escanear redes (airodump-ng)"
    printf "${YELLOW}║${NC} %-48s ${YELLOW}║${NC}\n" " 2) Ataque desautenticación manual"
    printf "${YELLOW}║${NC} %-48s ${YELLOW}║${NC}\n" " 3) Verificar handshake (.cap)"
    printf "${YELLOW}║${NC} %-48s ${YELLOW}║${NC}\n" " 4) Crackear contraseña (manual)"
    printf "${YELLOW}║${NC} %-48s ${YELLOW}║${NC}\n" " 5) Convertir .cap a .hc22000 (hashcat)"
    echo -e "${YELLOW}╠══════════════════════════════════════════════════╣${NC}"
    printf "${YELLOW}║${NC} %-48s ${YELLOW}║${NC}\n" " 6) Volver"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    read -p "Opción: " ext_opt
    case $ext_opt in
        1) scan_networks ;;
        2) deauth_attack ;;
        3) verify_handshake ;;
        4) crack_password ;;
        5) convert_cap_to_hc22000 ;;
        6) return ;;
    esac
}
