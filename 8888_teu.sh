#!/bin/bash

HOME_DIR="$HOME"
CONFIG_FILE="$HOME_DIR/.flask_proxies_config.json"

# Crear archivo JSON si no existe
if [ ! -f "$CONFIG_FILE" ]; then
    echo "{}" > "$CONFIG_FILE"
fi

# -----------------------------
# Funciones de manejo de JSON
# -----------------------------
function guardar_proxy() {
    local NAME=$1
    local URL=$2
    local PORT=$3
    jq --arg n "$NAME" --arg u "$URL" --arg p "$PORT" '.[$n] = {url: $u, port: ($p|tonumber)}' "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
}

function eliminar_proxy_config() {
    local NAME=$1
    jq "del(.\"$NAME\")" "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
}

function listar_proxies() {
    local COUNT
    COUNT=$(jq 'keys | length' "$CONFIG_FILE")
    if [ "$COUNT" -eq 0 ]; then
        echo "No hay proxies creados."
        return 1
    fi
    echo "Proxies existentes:"
    jq -r 'keys[]' "$CONFIG_FILE" | nl -w1 -s') '
    return 0
}

function seleccionar_proxy() {
    listar_proxies || return 1
    read -p "Seleccione el proxy por número: " num
    local NAME
    NAME=$(jq -r "keys[$((num-1))]" "$CONFIG_FILE")
    echo "$NAME"
}

# -----------------------------
# Funciones de proxy
# -----------------------------
function crear_proxy() {
    read -p "Nombre del proxy (sin espacios, ej: proxy1): " NAME
    read -p "URL destino (ej: http://us1.cloudgt.xyz:8888/server/online): " URL
    read -p "Puerto local (ej: 8888): " PORT

    SCRIPT_PATH="$HOME_DIR/proxy_${NAME}.py"
    SERVICE_NAME="proxy_${NAME}.service"
    CHECK_URL="http://127.0.0.1:$PORT/server/online"

    if lsof -i :"$PORT" >/dev/null 2>&1; then
        echo "❌ Error: el puerto $PORT ya está en uso."
        return
    fi

    # Instalar dependencias
    if ! command -v python3 &> /dev/null; then
        sudo apt update
        sudo apt install -y python3 python3-venv python3-pip curl jq
    fi
    python3 -m pip install --upgrade pip
    python3 -m pip install flask requests

    # Crear script Flask
    cat <<EOF > "$SCRIPT_PATH"
from flask import Flask, request, jsonify
import requests

app = Flask(__name__)
TARGET_URL = '$URL'

@app.route('/server/online', methods=['GET'])
def proxy_request():
    try:
        response = requests.get(TARGET_URL, timeout=3)
        if response.status_code == 200:
            return response.text
        else:
            return jsonify({"error": "Error al obtener los datos del servidor original"}), 500
    except requests.exceptions.RequestException as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=$PORT)
EOF

    # Crear servicio systemd
    cat <<EOL | sudo tee /etc/systemd/system/$SERVICE_NAME >/dev/null
[Unit]
Description=Flask Proxy $NAME
After=network.target

[Service]
User=$(whoami)
WorkingDirectory=$HOME_DIR
ExecStart=/usr/bin/python3 $SCRIPT_PATH
Restart=always

[Install]
WantedBy=multi-user.target
EOL

    sudo systemctl daemon-reload
    sudo systemctl enable $SERVICE_NAME

    # Abrir puerto en firewall si ufw activo
    if sudo ufw status | grep -q "Status: active"; then
        sudo ufw allow $PORT
    fi

    # Iniciar servicio
    sudo systemctl start $SERVICE_NAME

    # Guardar configuración
    guardar_proxy "$NAME" "$URL" "$PORT"

    echo "✅ Proxy $NAME creado y funcionando en puerto $PORT"
}

function actualizar_proxy_url() {
    NAME=$(seleccionar_proxy) || return
    read -p "Nueva URL para $NAME: " NEW_URL
    PORT=$(jq -r ".\"$NAME\".port" "$CONFIG_FILE")
    SCRIPT_PATH="$HOME_DIR/proxy_${NAME}.py"
    SERVICE_NAME="proxy_${NAME}.service"

    cat <<EOF > "$SCRIPT_PATH"
from flask import Flask, request, jsonify
import requests

app = Flask(__name__)
TARGET_URL = '$NEW_URL'

@app.route('/server/online', methods=['GET'])
def proxy_request():
    try:
        response = requests.get(TARGET_URL, timeout=3)
        if response.status_code == 200:
            return response.text
        else:
            return jsonify({"error": "Error al obtener los datos del servidor original"}), 500
    except requests.exceptions.RequestException as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=$PORT)
EOF

    sudo systemctl restart "$SERVICE_NAME"
    guardar_proxy "$NAME" "$NEW_URL" "$PORT"
    echo "✅ Proxy $NAME actualizado a la nueva URL"
}

# Funciones básicas
function iniciar_proxy() { NAME=$(seleccionar_proxy) || return; sudo systemctl start "proxy_${NAME}.service"; echo "✅ Servicio proxy_${NAME} iniciado."; }
function detener_proxy() { NAME=$(seleccionar_proxy) || return; sudo systemctl stop "proxy_${NAME}.service"; echo "✅ Servicio proxy_${NAME} detenido."; }
function reiniciar_proxy() { NAME=$(seleccionar_proxy) || return; sudo systemctl restart "proxy_${NAME}.service"; echo "✅ Servicio proxy_${NAME} reiniciado."; }
function eliminar_proxy() {
    NAME=$(seleccionar_proxy) || return
    sudo systemctl stop "proxy_${NAME}.service"
    sudo systemctl disable "proxy_${NAME}.service"
    sudo rm -f "/etc/systemd/system/proxy_${NAME}.service"
    sudo systemctl daemon-reload
    rm -f "$HOME_DIR/proxy_${NAME}.py"
    eliminar_proxy_config "$NAME"
    echo "✅ Proxy $NAME eliminado"
}
function estado_proxy() { NAME=$(seleccionar_proxy) || return; sudo systemctl status "proxy_${NAME}.service"; }

# -----------------------------
# Restaurar proxies al iniciar script
# -----------------------------
function restaurar_proxies() {
    for NAME in $(jq -r 'keys[]' "$CONFIG_FILE"); do
        URL=$(jq -r ".\"$NAME\".url" "$CONFIG_FILE")
        PORT=$(jq -r ".\"$NAME\".port" "$CONFIG_FILE")
        SCRIPT_PATH="$HOME_DIR/proxy_${NAME}.py"
        SERVICE_NAME="proxy_${NAME}.service"

        # Crear script si no existe
        if [ ! -f "$SCRIPT_PATH" ]; then
            cat <<EOF > "$SCRIPT_PATH"
from flask import Flask, request, jsonify
import requests

app = Flask(__name__)
TARGET_URL = '$URL'

@app.route('/server/online', methods=['GET'])
def proxy_request():
    try:
        response = requests.get(TARGET_URL, timeout=3)
        if response.status_code == 200:
            return response.text
        else:
            return jsonify({"error": "Error al obtener los datos del servidor original"}), 500
    except requests.exceptions.RequestException as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=$PORT)
EOF
        fi

        # Crear servicio systemd si no existe
        if [ ! -f "/etc/systemd/system/$SERVICE_NAME" ]; then
            cat <<EOL | sudo tee /etc/systemd/system/$SERVICE_NAME >/dev/null
[Unit]
Description=Flask Proxy $NAME
After=network.target

[Service]
User=$(whoami)
WorkingDirectory=$HOME_DIR
ExecStart=/usr/bin/python3 $SCRIPT_PATH
Restart=always

[Install]
WantedBy=multi-user.target
EOL
            sudo systemctl daemon-reload
            sudo systemctl enable "$SERVICE_NAME"
        fi

        # Abrir puerto en firewall si ufw activo
        if sudo ufw status | grep -q "Status: active"; then
            sudo ufw allow "$PORT"
        fi

        # Iniciar servicio
        sudo systemctl start "$SERVICE_NAME"
    done
}

# Restaurar proxies automáticamente al iniciar script
restaurar_proxies

# -----------------------------
# Menú interactivo
# -----------------------------
while true; do
    echo "--------------------------------------"
    echo "      MENU MULTI-PROXY FLASK FINAL"
    echo "--------------------------------------"
    echo "1) Crear nuevo proxy"
    echo "2) Iniciar proxy"
    echo "3) Detener proxy"
    echo "4) Reiniciar proxy"
    echo "5) Eliminar proxy"
    echo "6) Ver estado de un proxy"
    echo "7) Actualizar URL de un proxy"
    echo "8) Salir"
    echo "--------------------------------------"
    read -p "Seleccione una opción [1-8]: " opcion

    case $opcion in
        1) crear_proxy ;;
        2) iniciar_proxy ;;
        3) detener_proxy ;;
        4) reiniciar_proxy ;;
        5) eliminar_proxy ;;
        6) estado_proxy ;;
        7) actualizar_proxy_url ;;
        8) echo "Saliendo..."; exit 0 ;;
        *) echo "Opción inválida, intente de nuevo." ;;
    esac
done
