#!/bin/bash

echo "===================================================="
echo "      INSTALADOR AUTOMÁTICO - MULTI PROXY PYTHON"
echo "===================================================="

INSTALL_DIR="/opt/multiproxy"
mkdir -p $INSTALL_DIR

echo ""
echo "¿Cuántos proxys deseas crear?"
read -p "Número de proxys: " TOTAL

if ! [[ "$TOTAL" =~ ^[0-9]+$ ]]; then
    echo "Número inválido."
    exit 1
fi

# --- Generar un proxy por cada configuración ---
for (( i=1; i<=TOTAL; i++ ))
do
    echo ""
    echo "Configuración del Proxy $i"
    echo "---------------------------------"

    read -p "target_host $i: " TARGET_HOST
    read -p "target_port $i: " TARGET_PORT
    read -p "listen_port (puerto local) $i: " LISTEN_PORT

    PROXY_DIR="$INSTALL_DIR/proxy_$i"
    mkdir -p $PROXY_DIR

    # Guardar configuración
    cat <<EOF > $PROXY_DIR/config.txt
target_host=$TARGET_HOST
target_port=$TARGET_PORT
listen_port=$LISTEN_PORT
EOF

    # Script Python del proxy
    cat << 'EOF' > $PROXY_DIR/proxy_server.py
import http.server
import urllib.request
import os

def read_config():
    with open("config.txt", "r") as f:
        lines = f.read().splitlines()
        host = lines[0].split("=")[1]
        port = int(lines[1].split("=")[1])
        listen = int(lines[2].split("=")[1])
        return host, port, listen

target_host, target_port, listen_port = read_config()

class ProxyHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        try:
            url = f"http://{target_host}:{target_port}{self.path}"
            content_length = int(self.headers.get("Content-Length", 0))
            post_data = self.rfile.read(content_length)

            req = urllib.request.Request(url, data=post_data, headers=self.headers, method="POST")
            response = urllib.request.urlopen(req)

            self.send_response(response.getcode())
            for h, v in response.headers.items():
                self.send_header(h, v)
            self.end_headers()
            self.wfile.write(response.read())

        except Exception as e:
            self.send_error(500, str(e))

if __name__ == "__main__":
    server = http.server.HTTPServer(("0.0.0.0", listen_port), ProxyHandler)
    print(f"Proxy escuchando en puerto {listen_port} -> {target_host}:{target_port}")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass

    server.server_close()
EOF

    # Crear servicio systemd
    SERVICE_FILE="/etc/systemd/system/multiproxy_$i.service"

    cat <<EOF > $SERVICE_FILE
[Unit]
Description=Python Multi Proxy $i
After=network.target

[Service]
ExecStart=/usr/bin/python3 $PROXY_DIR/proxy_server.py
WorkingDirectory=$PROXY_DIR
Restart=always
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

    echo " → Activando servicio multiproxy_$i..."
    systemctl daemon-reload
    systemctl enable multiproxy_$i.service
    systemctl restart multiproxy_$i.service

done

echo ""
echo "===================================================="
echo " INSTALACIÓN COMPLETADA"
echo " Se han creado $TOTAL proxys."
echo " Cada uno se iniciará automáticamente en cada reinicio."
echo "===================================================="

systemctl --no-pager | grep multiproxy
