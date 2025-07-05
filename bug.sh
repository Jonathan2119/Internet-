#!/bin/sh

# --- CONFIGURACIONES INICIALES ---
API_URL="http://kelvin.conexioan.com:8080/verificar"
HOST_FILE="claro.com.do.txt"
CONFIG_DIR=".bugx_config"
BUG_DIR="bugscanner"
ACCESS_FILE="$CONFIG_DIR/acceso"
EXPIRA_FILE="$CONFIG_DIR/expira"
VERIFY_FILE="$CONFIG_DIR/verify"
CLAVE="$2"
MODO_MANUAL=false
[[ "$3" == "-m" ]] && MODO_MANUAL=true
INTERVALO_MINUTOS=20
[[ "$3" == "-t" ]] && INTERVALO_MINUTOS="${4:-20}"
[[ "$4" == "-t" ]] && INTERVALO_MINUTOS="${5:-20}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

crear_config_dir() {
    if [ ! -d "$CONFIG_DIR" ]; then
        mkdir -p "$CONFIG_DIR"
        chmod 700 "$CONFIG_DIR"
    fi
}

generate_hash() {
    echo -n "$1$2" | md5sum | awk '{print $1}'
    # Si md5sum no funciona en iSH usa:
    # echo -n "$1$2" | openssl md5 | awk '{print $2}'
}

encrypt_data() {
    echo "$1" | base64
}

decrypt_data() {
    echo "$1" | base64 -d
}

BANNER() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════════╗"
    echo -e "║         INTERNET BUG MÓVIL ${RED}🇩🇴${BLUE}               ║"
    echo -e "║   Desarrollador: ${YELLOW}JVM ${RED}🇩🇴${BLUE}               ║"
    echo -e "║   Telegram: https://t.me/+RvQMjiCgER5mYTYx ║"
    echo -e "╚════════════════════════════════════════════╝${NC}\n"
}

VALIDAR_CLAVE() {
    if [[ ! "$CLAVE" =~ ^[a-zA-Z0-9]{4,}$ ]]; then
        echo -e "${RED}[✘] Clave inválida: formato incorrecto.${NC}"
        exit 1
    fi

    echo -e "${YELLOW}[*] Validando clave en el servidor...${NC}"
    RESPUESTA=$(curl -s --max-time 10 -X POST "$API_URL" -H "Content-Type: application/json" -d "{\"id\": \"$CLAVE\"}" 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo -e "${RED}[✘] Error de conexión. Verifica tu internet.${NC}"
        if [ -f "$ACCESS_FILE" ]; then
            echo -e "${YELLOW}[!] Usando clave local para continuar.${NC}"
            cargar_clave_local
            return 0
        else
            echo -e "${RED}[✘] No hay clave local guardada. Saliendo.${NC}"
            exit 1
        fi
    fi

    ESTADO=$(echo "$RESPUESTA" | grep -o '"status": *"[^"]*"' | awk -F'"' '{print $4}')
    EXPIRA=$(echo "$RESPUESTA" | grep -o '"expira": *"[^"]*"' | awk -F'"' '{print $4}')

    if [ "$ESTADO" = "permitido" ]; then
        echo -e "${GREEN}[✔] Clave válida. Guardando autorización...${NC}"
        guardar_clave "$CLAVE" "$EXPIRA"
        echo -e "${GREEN}[✔] Acceso válido hasta: $EXPIRA UTC${NC}"
        return 0
    else
        echo -e "${RED}[✘] Clave inválida o expirada.${NC}"
        if [ -f "$ACCESS_FILE" ]; then
            echo -e "${YELLOW}[!] Usando clave local para continuar.${NC}"
            cargar_clave_local
            return 0
        else
            exit 1
        fi
    fi
}

guardar_clave() {
    local clave="$1"
    local expira="$2"

    crear_config_dir
    encrypt_data "$clave" > "$ACCESS_FILE"
    encrypt_data "$expira" > "$EXPIRA_FILE"
    local verify_hash
    verify_hash=$(generate_hash "$clave" "$expira")
    encrypt_data "$verify_hash" > "$VERIFY_FILE"
    chmod 600 "$ACCESS_FILE" "$EXPIRA_FILE" "$VERIFY_FILE"
}

cargar_clave_local() {
    if [ -f "$ACCESS_FILE" ] && [ -f "$EXPIRA_FILE" ] && [ -f "$VERIFY_FILE" ]; then
        CLAVE=$(decrypt_data "$(cat "$ACCESS_FILE")")
        local expira
        expira=$(decrypt_data "$(cat "$EXPIRA_FILE")")
        local stored_hash
        stored_hash=$(decrypt_data "$(cat "$VERIFY_FILE")")
        local calculated_hash
        calculated_hash=$(generate_hash "$CLAVE" "$expira")
        if [ "$stored_hash" != "$calculated_hash" ]; then
            echo -e "${RED}[✘] Archivos de acceso alterados.${NC}"
            exit 1
        fi
    else
        echo -e "${RED}[✘] Archivos de acceso incompletos.${NC}"
        exit 1
    fi
}

CHEQUEAR_EXPIRACION() {
    if [ -f "$EXPIRA_FILE" ]; then
        local expira_enc
        expira_enc=$(cat "$EXPIRA_FILE")
        local EXPIRA_LOCAL
        EXPIRA_LOCAL=$(decrypt_data "$expira_enc")
        AHORA=$(date -u +"%Y-%m-%dT%H:%M:%S")
        EXPIRA_TS=$(date -d "$(echo "$EXPIRA_LOCAL" | sed 's/T/ /')" +%s)
        AHORA_TS=$(date -d "$(echo "$AHORA" | sed 's/T/ /')" +%s)
        if [ "$AHORA_TS" -gt "$EXPIRA_TS" ]; then
            echo -e "${RED}[✘] Acceso expirado. Eliminando autorización.${NC}"
            rm -f "$ACCESS_FILE" "$EXPIRA_FILE" "$VERIFY_FILE"
            echo -e "${RED}[✘] Tu archivo ha expirado. Contacta al grupo para renovar tu acceso.${NC}"
            exit 1
        fi
    fi
}

verificar_dependencias() {
    [ -f "$CONFIG_DIR/.deps_ok" ] && return 0

    command -v python3 >/dev/null 2>&1 || {
        echo -e "${YELLOW}[!] Instalando Python3...${NC}"
        apk update >/dev/null 2>&1 && apk add python3 py3-pip py3-setuptools
    }

    instalar_modulo_si_falta() {
        local modulo="$1"
        python3 -c "import $modulo" 2>/dev/null || {
            echo -e "${YELLOW}[!] Instalando módulo $modulo...${NC}"
            pip3 install "$modulo" --break-system-packages >/dev/null 2>&1
        }
    }

    instalar_modulo_si_falta "requests"
    instalar_modulo_si_falta "loguru"

    mkdir -p "$CONFIG_DIR"
    touch "$CONFIG_DIR/.deps_ok"
}

DESCARGAR_HOSTS() {
    [ ! -f "$HOST_FILE" ] && curl -s -O "https://raw.githubusercontent.com/Ivangabriel21210/HoliDocker/main/$HOST_FILE"
}

EJECUTAR_BUG() {
    echo -e "${BLUE}📡 Ejecutando Host puerto TCP...${NC}"
    python3 -c "
import os, sys, requests
from concurrent.futures import ThreadPoolExecutor
sys.stdout = open(os.devnull, 'w')
sys.stderr = open(os.devnull, 'w')
with open('$HOST_FILE') as f:
    hosts = [line.strip() for line in f if line.strip()]
def check_host(host):
    try:
        requests.head(f'https://{host}', timeout=3, verify=False, allow_redirects=False).close()
    except: pass
with ThreadPoolExecutor(max_workers=100) as executor:
    executor.map(check_host, hosts)
"
    echo -e "${BLUE}📡 Ejecutando Host puerto UDP...${NC}"
    python3 -c "
import os, sys, requests
from concurrent.futures import ThreadPoolExecutor
sys.stdout = open(os.devnull, 'w')
sys.stderr = open(os.devnull, 'w')
with open('$HOST_FILE') as f:
    hosts = [line.strip() for line in f if line.strip()]
def check_host(host):
    try:
        requests.head(f'http://{host}', timeout=3, verify=False, allow_redirects=False).close()
    except: pass
with ThreadPoolExecutor(max_workers=103) as executor:
    executor.map(check_host, hosts)
"
    rm -rf bugscanner >/dev/null 2>&1
}

HACER_CURL() {
    curl -I https://miclaroempresas.claro.com.do >/dev/null 2>&1
    curl -I http://miclaroempresas.claro.com.do >/dev/null 2>&1
}

VERIFICAR_CONEXION() {
    local conexion_activa=true
    local ya_notificado=false

    echo -e "${YELLOW}[•] Esperando 25 minutos antes de comenzar el monitoreo de conexión...${NC}"
    sleep 1500

    while true; do
        if ! curl -s --max-time 5 https://google.com >/dev/null; then
            if $conexion_activa; then
                conexion_activa=false
                ya_notificado=false
                echo -e "${RED}[✘] Conexión caída detectada. Ejecutando BUG...${NC}"
                touch /tmp/.recovery.lock
                EJECUTAR_BUG
                HACER_CURL
                if ! $MODO_MANUAL; then
                    ACTIVAR_INTERNET
                fi
                echo -e "${YELLOW}[*] Esperando 2 minutos para verificar nuevamente...${NC}"
                sleep 120
                rm -f /tmp/.recovery.lock
            elif ! $ya_notificado; then
                echo -e "${RED}[✘] Aún sin conexión...${NC}"
                ya_notificado=true
            fi
        else
            if ! $conexion_activa; then
                echo -e "${GREEN}[✔] Conexión restaurada. Reanudando monitoreo...${NC}"
                conexion_activa=true
                ya_notificado=false
                sleep 120
            fi
        fi
        sleep 30
    done
}

ACTIVAR_INTERNET() {
    if curl -s --max-time 5 https://google.com >/dev/null; then
        echo -e "${GREEN}[✔] Ya tienes internet. No se necesita activar.${NC}"
        return
    fi
    echo -e "${BLUE}[•] Activando internet...${NC}"
    for i in {1..3}; do
        curl --max-time 2 https://contenedor.smapps.mx >/dev/null 2>&1
        curl --max-time 2 http://contenedor.smapps.mx >/dev/null 2>&1
        curl --max-time 2 https://apk.ctn.smapps.mx >/dev/null 2>&1
        curl --max-time 2 https://apk.ctn.smapps.mx:9852 >/dev/null 2>&1
        curl --max-time 2 https://www.clarovr.com >/dev/null 2>&1
        curl --max-time 2 https://omicron.banreservas.com:5443 >/dev/null 2>&1
        curl --max-time 2 https://claro.clubapps.com.do >/dev/null 2>&1
    done
    echo -e "${YELLOW}[•] Esperando 1 minuto para verificar conexión...${NC}"
    sleep 60
    if curl -s --max-time 5 https://google.com >/dev/null; then
        echo -e "${GREEN}[✔] Ya tienes internet, Prueba en https://fast.com${NC}"
        return
    fi
    echo -e "${YELLOW}[•] Aún sin conexión. Esperando 20 segundos más...${NC}"
    sleep 20
    if curl -s --max-time 5 https://google.com >/dev/null; then
        echo -e "${GREEN}[✔] Ya tienes internet, Prueba en https://fast.com${NC}"
    else
        echo -e "${RED}[✘] No se logró activar internet, Intenta modo avión.${NC}"
    fi
}

MAIN_LOOP() {
    while true; do
        CHEQUEAR_EXPIRACION

        if [ ! -f /tmp/.recovery.lock ]; then
            EJECUTAR_BUG
            HACER_CURL
            if [ "$MODO_MANUAL" = false ]; then
                ACTIVAR_INTERNET
            fi
        else
            echo -e "${YELLOW}[!] MAIN_LOOP: Saltado porque recuperación está activa.${NC}"
        fi

        echo -e "${YELLOW}[*] Intentando actualizar expiración desde API...${NC}"
        VALIDAR_CLAVE

        echo -e "${YELLOW}[*] Esperando $INTERVALO_MINUTOS minutos para la próxima ejecución...${NC}"
        TIEMPO_SEGUNDOS=$(expr "$INTERVALO_MINUTOS" \* 60)
        i=$TIEMPO_SEGUNDOS
        while [ "$i" -gt 0 ]; do
            min=$((i / 60))
            sec=$((i % 60))
            printf "\rTiempo restante: %02d:%02d" "$min" "$sec"
            sleep 1
            i=$((i - 1))
        done
        echo
    done
}


BANNER
verificar_dependencias
if [ "$1" != "-cl" ] || [ -z "$CLAVE" ]; then
    echo "Utiliza: ./bug.sh -cl <clave>"
    exit 1
fi
crear_config_dir
[ ! -f "$ACCESS_FILE" ] && VALIDAR_CLAVE || { cargar_clave_local; CHEQUEAR_EXPIRACION; }
DESCARGAR_HOSTS
VERIFICAR_CONEXION &
MAIN_LOOP
