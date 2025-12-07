#!/bin/bash

# -----------------------------
# Configuración inicial
# -----------------------------
USER=$(whoami)
HOME_DIR="$HOME"
SCRIPT_PATH="$HOME_DIR/proxy_flask.py"
SERVICE_NAME="proxyflask.service"
LOG_PATH="$HOME_DIR/proxy_flask.log"

# -----------------------------
# 1️⃣ Instalar Python3 y pip si no existen
# -----------------------------
echo "Verificando Python3..."
if ! command -v python3 &> /dev/null; then
    echo "Python3 no está instalado. Instalando..."
    sudo apt update
    sudo apt install -y python3 python3-venv python3-pip
else
    echo "Python3 ya está instalado."
fi

# -----------------------------
# 2️⃣ Instalar dependencias de Python
# -----------------------------
echo "Instalando Flask y requests..."
python3 -m pip install --upgrade pip
python3 -m pip install flask requests

# -----------------------------
# 3️⃣ Crear el script Flask
# -----------------------------
echo "Creando script Flask en $SCRIPT_PATH ..."

cat << 'EOF' > "$SCRIPT_PATH"
from flask import Flask, request, jsonify
import requests

app = Flask(__name__)

TARGET_URL = 'http://us1.cloudgt.xyz:8888/server/online'

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
    app.run(host='0.0.0.0', port=8888)
EOF

if [ -f "$SCRIPT_PATH" ]; then
    echo "✅ Script Flask creado correctamente."
else
    echo "❌ Error: no se pudo crear el script Flask."
    exit 1
fi

# -----------------------------
# 4️⃣ Crear archivo de servicio systemd
# -----------------------------
echo "Creando servicio systemd $SERVICE_NAME ..."

SERVICE_FILE="/tmp/$SERVICE_NAME"

cat <<EOL > $SERVICE_FILE
[Unit]
Description=Flask Proxy Server
After=network.target

[Service]
User=$USER
WorkingDirectory=$HOME_DIR
ExecStart=/usr/bin/python3 $SCRIPT_PATH
Restart=always
StandardOutput=file:$LOG_PATH
StandardError=file:$LOG_PATH

[Install]
WantedBy=multi-user.target
EOL

sudo mv $SERVICE_FILE /etc/systemd/system/$SERVICE_NAME

# -----------------------------
# 5️⃣ Habilitar y arrancar el servicio
# -----------------------------
sudo systemctl daemon-reload
sudo systemctl enable $SERVICE_NAME
sudo systemctl start $SERVICE_NAME

echo "--------------------------------------"
echo "✅ Servicio Flask instalado y en ejecución"
echo "Logs: $LOG_PATH"
echo "Estado del servicio: sudo systemctl status $SERVICE_NAME"
