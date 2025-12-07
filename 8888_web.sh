#!/bin/bash

HOME_DIR="$HOME"
APP_FILE="$HOME_DIR/flask_proxy_enterprise.py"
SERVICE_NAME="flask_proxy_enterprise.service"

echo "🔹 Dominio requerido para HTTPS automático"
read -p "Ingrese su dominio: " DOMAIN
if [ -z "$DOMAIN" ]; then
  echo "❌ Debe ingresar un dominio válido."
  exit 1
fi
EMAIL="admin@$DOMAIN"

# -------------------------------------
# Instalar dependencias
# -------------------------------------
sudo apt update
sudo apt install -y python3 python3-pip python3-venv curl jq ufw certbot nginx
python3 -m pip install --upgrade pip
python3 -m pip install flask requests

# -------------------------------------
# Configurar firewall
# -------------------------------------
sudo ufw allow 80
sudo ufw allow 443
sudo ufw --force enable

# -------------------------------------
# HTTPS automático
# -------------------------------------
sudo systemctl stop nginx
sudo certbot certonly --standalone --non-interactive --agree-tos -m "$EMAIL" -d "$DOMAIN"
CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
if [ ! -f "$CERT" ]; then
  echo "❌ Error generando certificado."
  exit 1
fi

# -------------------------------------
# Crear Flask ENTERPRISE
# -------------------------------------
cat <<EOF > "$APP_FILE"
#!/usr/bin/env python3
from flask import Flask, request, jsonify, render_template_string, redirect, url_for, Response
import subprocess, os, json, threading, requests, time, base64

HOME=os.path.expanduser("~")
CONFIG=HOME+"/.proxy_enterprise.json"
if not os.path.exists(CONFIG): json.dump({}, open(CONFIG,"w"))

app=Flask(__name__)
USERNAME="admin"
PASSWORD="admin"  # Cambiar después para mayor seguridad

PROXY_STATUS={}

def load(): return json.load(open(CONFIG))
def save(c): json.dump(c, open(CONFIG,"w"), indent=2)
def sh(cmd): subprocess.call(cmd, shell=True)

def check_auth(auth_header):
    if not auth_header: return False
    method, encoded = auth_header.split(None,1)
    if method.lower() != "basic": return False
    decoded=base64.b64decode(encoded).decode()
    u,p=decoded.split(":",1)
    return u==USERNAME and p==PASSWORD

def auth_required(f):
    def decorated(*args, **kwargs):
        from flask import request, Response
        if not check_auth(request.headers.get("Authorization")):
            return Response("Login Required",401,{"WWW-Authenticate":'Basic realm="Login Required"'})
        return f(*args, **kwargs)
    decorated.__name__=f.__name__
    return decorated

def create_script(name,url,port):
    f=HOME+f"/proxy_{name}.py"
    open(f,"w").write(f'''
from flask import Flask, jsonify
import requests
app=Flask(__name__)
TARGET="{url}"
@app.route("/server/online")
def s():
    try: r=requests.get(TARGET,timeout=3)
        return r.text if r.status_code==200 else jsonify({{"error":"fail"}}),500
    except: return jsonify({{"error":"fail"}}),500
app.run(host="0.0.0.0",port={port},ssl_context=("{CERT}","{KEY}"))
''')
    return f

def service(name,script):
    unit=f"""
[Unit]
Description=proxy {name}
After=network.target
[Service]
User={os.getlogin()}
ExecStart=/usr/bin/python3 {script}
Restart=always
StandardOutput=null
StandardError=null
[Install]
WantedBy=multi-user.target
"""
    open("/tmp/x","w").write(unit)
    sh(f"sudo mv /tmp/x /etc/systemd/system/proxy_{name}.service")
    sh("sudo systemctl daemon-reload")
    sh(f"sudo systemctl enable proxy_{name}.service")
    sh(f"sudo systemctl restart proxy_{name}.service")

def monitor():
    global PROXY_STATUS
    while True:
        cfg=load()
        for n,d in cfg.items():
            try:
                r=requests.get(f"https://127.0.0.1:{d['port']}/server/online",verify=False,timeout=2)
                PROXY_STATUS[n]={"status":"UP","latency":round(r.elapsed.total_seconds()*1000,2)}
            except:
                PROXY_STATUS[n]={"status":"DOWN","latency":0}
                sh(f"sudo systemctl restart proxy_{n}.service")
        time.sleep(5)

threading.Thread(target=monitor,daemon=True).start()

# -------------------------------------
# Rutas ENTERPRISE
# -------------------------------------
@app.route("/")
@auth_required
def home():
    cfg=load()
    global PROXY_STATUS
    labels=[]
    data=[]
    for n,d in cfg.items():
        labels.append(n)
        latency=PROXY_STATUS.get(n,{}).get("latency",0)
        data.append(latency)
    html="""
<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Proxy Manager HTTPS ENTERPRISE</title>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.2/dist/css/bootstrap.min.css" rel="stylesheet">
<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
</head>
<body class="bg-light">
<div class="container py-4">
<h1 class="mb-4">Proxy Manager HTTPS ENTERPRISE</h1>

<div class="card mb-4">
<div class="card-body">
<h5>Crear Nuevo Proxy</h5>
<form method="post" action="/create">
<div class="mb-2"><input name="name" placeholder="Nombre" class="form-control" required></div>
<div class="mb-2"><input name="url" placeholder="URL destino" class="form-control" required></div>
<div class="mb-2"><input name="port" placeholder="Puerto local" type="number" class="form-control" required></div>
<button class="btn btn-primary">Crear</button>
</form>
</div></div>

<div class="card mb-4"><div class="card-body">
<h5>Proxies Activos</h5>
<table class="table table-striped">
<tr><th>Nombre</th><th>URL</th><th>Puerto</th><th>Estado</th><th>Latencia(ms)</th><th>Acciones</th></tr>
"""
    for n,d in cfg.items():
        status=PROXY_STATUS.get(n,{}).get("status","UNKNOWN")
        latency=PROXY_STATUS.get(n,{}).get("latency",0)
        color="green" if status=="UP" else "red"
        html+=f"<tr><td>{n}</td><td>{d['url']}</td><td>{d['port']}</td>"
        html+=f"<td style='color:{color}'>{status}</td>"
        html+=f"<td>{latency}</td>"
        html+=f"<td><a class='btn btn-sm btn-warning' href='/restart/{n}'>Reiniciar</a> "
        html+=f"<a class='btn btn-sm btn-danger' href='/delete/{n}'>Eliminar</a></td></tr>"
    html+="""</table></div></div>

<div class="card mb-4"><div class="card-body">
<h5>Latencias de Proxies</h5>
<canvas id="latencyChart"></canvas>
<script>
var ctx = document.getElementById('latencyChart').getContext('2d');
var chart = new Chart(ctx, {
    type: 'bar',
    data: {
        labels: """ + str(labels) + """,
        datasets: [{
            label: 'Latencia(ms)',
            backgroundColor: 'blue',
            data: """ + str(data) + """
        }]
    },
    options: {responsive:true, maintainAspectRatio:false}
});
</script>
</div></div>

<div class="card mb-4"><div class="card-body">
<h5>Exportar Configuración</h5>
<a href="/export" class="btn btn-secondary">Exportar JSON</a>
<form method="post" action="/import" enctype="multipart/form-data" class="mt-2">
<input type="file" name="file" class="form-control mb-2" required>
<button class="btn btn-primary">Importar JSON</button>
</form>
</div></div>

</div></body></html>
"""
    return html

@app.route("/create",methods=["POST"])
@auth_required
def create():
    name=request.form["name"]
    url=request.form["url"]
    port=int(request.form["port"])
    cfg=load()
    cfg[name]={"url":url,"port":port}
    save(cfg)
    script=create_script(name,url,port)
    service(name,script)
    sh(f"sudo ufw allow {port}")
    return redirect("/")

@app.route("/restart/<name>")
@auth_required
def restart(name):
    sh(f"sudo systemctl restart proxy_{name}.service")
    return redirect("/")

@app.route("/delete/<name>")
@auth_required
def delete(name):
    cfg=load()
    if name in cfg: del cfg[name]
    save(cfg)
    sh(f"sudo systemctl stop proxy_{name}.service")
    sh(f"sudo systemctl disable proxy_{name}.service")
    sh(f"sudo rm /etc/systemd/system/proxy_{name}.service")
    sh("sudo systemctl daemon-reload")
    return redirect("/")

@app.route("/export")
@auth_required
def export_cfg():
    return Response(open(CONFIG).read(), mimetype="application/json",
                    headers={"Content-Disposition":"attachment; filename=proxy_config.json"})

@app.route("/import",methods=["POST"])
@auth_required
def import_cfg():
    file=request.files["file"]
    data=json.load(file)
    save(data)
    return redirect("/")

app.run(host="0.0.0.0",port=443,ssl_context=("{CERT}","{KEY}"))
EOF

chmod +x "$APP_FILE"

# -------------------------------------
# Servicio systemd ENTERPRISE
# -------------------------------------
cat <<EOF | sudo tee /etc/systemd/system/$SERVICE_NAME >/dev/null
[Unit]
Description=Flask Proxy Panel ENTERPRISE HTTPS
After=network.target
[Service]
User=$(whoami)
ExecStart=/usr/bin/python3 $APP_FILE
Restart=always
StandardOutput=null
StandardError=null
[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable $SERVICE_NAME
sudo systemctl restart $SERVICE_NAME

echo "🎉 Panel ENTERPRISE instalado y corriendo en: https://$DOMAIN"
echo "🔐 Usuario/Contraseña por defecto: admin/admin (Cambiar inmediatamente)"
echo "✅ Gestión completa, gráficos, export/import y monitoreo en tiempo real."
