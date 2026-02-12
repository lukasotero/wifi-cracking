# WiFi Cracking

Este proyecto te ayuda a automatizar el proceso de obtener contraseñas de redes WiFi de manera sencilla. No necesitas ser un experto, el script hace casi todo por ti.

## ¿Qué hace esto?

Este script está diseñado para auditar redes **WPA y WPA2-Personal (PSK)**.
**NO funcionará** con:
*   Redes antiguas WEP.
*   Redes nuevas WPA3.
*   Redes Enterprise (las que piden usuario y contraseña).

### Métodos de Ataque Disponibles:

1.  **Handshake WPA (Clásico)**:
    *   Desconecta a un usuario y captura su reconexión.
    *   Requiere esperar a que haya alguien conectado.
    *   **Se crackea con diccionario**.

2.  **Ataque PMKID (Sin clientes)**:
    *   Ataca directamente al Router para obtener el hash.
    *   **No necesita usuarios conectados** (Client-less).
    *   **Se crackea con diccionario** (igual que el Handshake).

3.  **Ataque WPS (Pixie Dust)**:
    *   Explota una vulnerabilidad en el sistema WPS del router.
    *   **NO usa diccionarios**: Intenta recuperar el PIN y la contraseña directamente.
    *   Es muy rápido (segundos/minutos) si el router es vulnerable.

**IMPORTANTE:** Si usas ataques de diccionario (1 y 2), recuerda que si la contraseña no está en tu lista, no podrás obtenerla.

## Flujo de Trabajo

El menú principal te ofrece 3 métodos directos:

1.  **Ataque WPA/WPA2 Clásico**:
    *   Captura handshake y lanza ataques de desautenticación automáticamente.
    *   Si captura, verificará el archivo y te ofrecerá crackearlo al instante.

2.  **Ataque WPS**:
    *   Busca redes vulnerables y lanza Pixie Dust.

3.  **Ataque PMKID (Client-less)**:
    *   Ataca un objetivo específico o todos los cercanos.
    *   Si captura PMKID, lo convierte y te ofrece crackearlo con GPU.

También tienes un menú de **Herramientas Extra** para realizar tareas manuales (escanear, deauth, crackear manualmente, etc.).

## Requisito Importante

**Tu tarjeta de red debe soportar "Modo Monitor".**
Muchas tarjetas WiFi integradas en portátiles no tienen esta función. Si la tuya no lo soporta, necesitarás comprar un adaptador USB WiFi compatible.

## ¿Cómo se usa?

Solo necesitas abrir tu terminal en Kali Linux (o similar) y seguir estos 3 pasos:

1.  **Descargar el proyecto:**
    ```bash
    git clone https://github.com/lukasotero/wifi-cracking.git
    cd wifi-cracking
    ```

2.  **Dar permisos:**
    ```bash
    chmod +x wifi_cracking.sh
    ```

3.  **Ejecutar:**
    ```bash
    sudo ./wifi_cracking.sh
    ```

¡Listo! El programa te irá preguntando qué quieres hacer en cada paso. Si te faltan programas necesarios, él mismo te ofrecerá instalarlos.

> **Nota:** Úsalo solo en redes que sean tuyas o tengas permiso para auditar.
