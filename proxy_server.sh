#!/bin/bash

echo "===================================================="
echo "      INSTALADOR AUTOMÁTICO - PYTHON PROXY-SERVER"
echo "===================================================="

# --- 1. PEDIR CONFIGURACIÓN INICIAL ---

read -p "Introduce el target_host (ej: tudominio.com): " TARGET_HOST
read -p "Introduce el target_port (ej: 5454): " TARGET_PORT

# --- 2. CREAR CARPETA DEL PROYECTO ---

INSTALL_DIR="/opt/proxyserver"
mkdir -p $INSTALL_DIR

echo "Creando archivos en $INSTALL_DIR..."

# --- 3. GUARDAR CONFIGURACIÓN ---
cat <<EOF > $INSTALL_DIR/config.txt
target_host=$TARGET_HOST
target_port=$TARGET_PORT
EOF

# --- 4. CREAR SCRIPT PYTHON DEL PROXY ---

cat <<'EOF' > $INSTALL_DIR/proxy_server.py
import http.server
import urllib.request
import os

# Leer configuración
def read_config():
    with open("config.txt", "r") as f:
        lines = f.read().splitlines()
        host = lines[0].split("=")[1]
        port = int(lines[1].split("=")[1])
        return host, port

target_host, target_port = read_config()

class ProxyHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        try:
            url = f'http://{target_host}:{target_port}{self.path}'
            
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length)

            req = urllib.request.Request(url, data=post_data, headers=self.headers, method='POST')
            response = urllib.request.urlopen(req)

            self.send_response(response.getcode())
            for h, v in response.headers.items():
                self.send_header(h, v)
            self.end_headers()

            self.wfile.write(response.read())

        except Exception as e:
            self.send_error(500, str(e))

if __name__ == "__main__":
    proxy_host = "0.0.0.0"
    proxy_port = 5454

    server = http.server.HTTPServer((proxy_host, proxy_port), ProxyHandler)
    print(f"Proxy iniciado en {proxy_host}:{proxy_port}")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass

    server.server_close()
    print("Proxy cerrado.")
EOF

# --- 5. INSTALAR PYTHON (SI NO EXISTE) ---
echo "Instalando Python3..."
apt-get update -y
apt-get install -y python3 python3-pip

# --- 6. CREAR SERVICIO SYSTEMD ---

SERVICE_FILE="/etc/systemd/system/proxyserver.service"

cat <<EOF > $SERVICE_FILE
[Unit]
Description=Python Proxy Server
After=network.target

[Service]
ExecStart=/usr/bin/python3 $INSTALL_DIR/proxy_server.py
WorkingDirectory=$INSTALL_DIR
Restart=always
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

# --- 7. ACTIVAR SERVICIO ---

echo "Activando servicio..."
systemctl daemon-reload
systemctl enable proxyserver.service
systemctl restart proxyserver.service

echo "===================================================="
echo " INSTALACIÓN COMPLETA "
echo " El proxy está corriendo y arrancará en cada reinicio."
echo "===================================================="

systemctl status proxyserver.service --no-pager
