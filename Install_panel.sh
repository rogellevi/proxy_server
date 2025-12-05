#!/bin/bash

echo "==============================================="
echo " INSTALADOR DEL PANEL WEB MULTIPROXY"
echo "==============================================="

# 1. Actualizar sistema
apt update -y

# 2. Instalar Apache + PHP
apt install -y apache2 php libapache2-mod-php

# 3. Crear carpeta del panel
PANEL_DIR="/var/www/html/multiproxy"
mkdir -p $PANEL_DIR/templates

echo "Copiando archivos del panel..."

# ------------------- CSS -------------------
cat <<'EOF' > $PANEL_DIR/style.css
body {
    background: #f2f2f2;
    font-family: Arial, sans-serif;
    padding: 20px;
}
.container {
    background: white;
    padding: 20px;
    border-radius: 10px;
    max-width: 900px;
    margin: auto;
    box-shadow: 0 0 10px rgba(0,0,0,0.1);
}
h1, h2 { text-align: center; }
table { width: 100%; border-collapse: collapse; margin-top: 20px; }
table th, table td { padding: 10px; border-bottom: 1px solid #ddd; }
button { padding: 7px 12px; border: none; border-radius: 5px; cursor: pointer; }
.btn-start { background: #27ae60; color: white; }
.btn-stop { background: #c0392b; color: white; }
.btn-edit { background: #2980b9; color: white; }
.btn-delete { background: #8e44ad; color: white; }
form input { width: 100%; padding: 8px; margin: 5px 0 15px; }
EOF

# ------------------- HEADER -------------------
cat <<'EOF' > $PANEL_DIR/templates/header.php
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Panel MultiProxy</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
<div class="container">
EOF

# ------------------- FOOTER -------------------
cat <<'EOF' > $PANEL_DIR/templates/footer.php
</div>
</body>
</html>
EOF

# ------------------- index.php ----------------------
cat <<'EOF' > $PANEL_DIR/index.php
<?php
include "templates/header.php";

$basePath = "/opt/multiproxy/";
$proxies = [];

foreach (glob($basePath . "proxy_*") as $dir) {
    $cfg = $dir . "/config.txt";
    if (file_exists($cfg)) {
        $lines = file($cfg, FILE_IGNORE_NEW_LINES);
        $data = [];
        foreach ($lines as $line) {
            list($k, $v) = explode("=", $line);
            $data[$k] = $v;
        }
        $id = basename($dir);
        $proxies[] = [
            "id" => str_replace("proxy_", "", $id),
            "target_host" => $data["target_host"],
            "target_port" => $data["target_port"],
            "listen_port" => $data["listen_port"],
        ];
    }
}
?>

<h1>Panel MultiProxy</h1>

<h2>Lista de Proxys</h2>

<table>
<tr>
    <th>ID</th>
    <th>Escucha</th>
    <th>Destino</th>
    <th>Acciones</th>
</tr>

<?php foreach ($proxies as $p): ?>
<tr>
    <td><?= $p["id"] ?></td>
    <td><?= $p["listen_port"] ?></td>
    <td><?= $p["target_host"] ?>:<?= $p["target_port"] ?></td>
    <td>
        <form method="POST" action="actions.php" style="display:inline;">
            <input type="hidden" name="id" value="<?= $p["id"] ?>">
            <button name="action" value="start" class="btn-start">Start</button>
        </form>

        <form method="POST" action="actions.php" style="display:inline;">
            <input type="hidden" name="id" value="<?= $p["id"] ?>">
            <button name="action" value="stop" class="btn-stop">Stop</button>
        </form>

        <a href="edit.php?id=<?= $p["id"] ?>">
            <button class="btn-edit">Editar</button>
        </a>

        <form method="POST" action="actions.php" style="display:inline;">
            <input type="hidden" name="id" value="<?= $p["id"] ?>">
            <button name="action" value="delete" class="btn-delete">Eliminar</button>
        </form>
    </td>
</tr>
<?php endforeach; ?>
</table>

<h2>Crear Nuevo Proxy</h2>

<form method="POST" action="actions.php">
    <input type="hidden" name="action" value="create">

    Target Host:
    <input type="text" name="target_host" required>

    Target Port:
    <input type="number" name="target_port" required>

    Puerto Local (listen_port):
    <input type="number" name="listen_port" required>

    <button class="btn-start">Crear Proxy</button>
</form>

<?php include "templates/footer.php"; ?>
EOF

# ------------------- actions.php ----------------------
cat <<'EOF' > $PANEL_DIR/actions.php
<?php
$basePath = "/opt/multiproxy/";
$action = $_POST["action"] ?? null;
$id = $_POST["id"] ?? null;

function serviceName($id) {
    return "multiproxy_" . $id . ".service";
}

switch ($action) {
    case "start":
        shell_exec("systemctl start " . serviceName($id));
        break;

    case "stop":
        shell_exec("systemctl stop " . serviceName($id));
        break;

    case "delete":
        shell_exec("systemctl stop " . serviceName($id));
        shell_exec("systemctl disable " . serviceName($id));
        unlink("/etc/systemd/system/" . serviceName($id));
        shell_exec("rm -rf $basePath/proxy_$id");
        shell_exec("systemctl daemon-reload");
        break;

    case "create":
        $host = $_POST["target_host"];
        $p1   = $_POST["target_port"];
        $lp   = $_POST["listen_port"];

        $id = count(glob($basePath . "proxy_*")) + 1;

        $dir = $basePath . "proxy_$id";
        mkdir($dir);

        file_put_contents("$dir/config.txt",
            "target_host=$host\n".
            "target_port=$p1\n".
            "listen_port=$lp"
        );

        shell_exec("cp /opt/multiproxy/proxy_1/proxy_server.py $dir/proxy_server.py");

        file_put_contents("/etc/systemd/system/multiproxy_$id.service",
"[Unit]
Description=Python Multi Proxy $id
After=network.target

[Service]
ExecStart=/usr/bin/python3 $dir/proxy_server.py
WorkingDirectory=$dir
Restart=always
User=root
Group=root

[Install]
WantedBy=multi-user.target"
        );

        shell_exec("systemctl daemon-reload");
        shell_exec("systemctl enable multiproxy_$id.service");
        shell_exec("systemctl start multiproxy_$id.service");
        break;

    case "edit":
        $host = $_POST["target_host"];
        $p1   = $_POST["target_port"];
        $lp   = $_POST["listen_port"];

        file_put_contents("$basePath/proxy_$id/config.txt",
            "target_host=$host\n".
            "target_port=$p1\n".
            "listen_port=$lp"
        );

        shell_exec("systemctl restart " . serviceName($id));
        break;
}

header("Location: index.php");
exit;
?>
EOF

# ------------------- edit.php ----------------------
cat <<'EOF' > $PANEL_DIR/edit.php
<?php
include "templates/header.php";

$id = $_GET["id"];
$path = "/opt/multiproxy/proxy_$id/config.txt";

$cfg = parse_ini_file($path);
?>

<h1>Editar Proxy <?= $id ?></h1>

<form method="POST" action="actions.php">
    <input type="hidden" name="action" value="edit">
    <input type="hidden" name="id" value="<?= $id ?>">

    Target Host:
    <input type="text" name="target_host" value="<?= $cfg['target_host'] ?>">

    Target Port:
    <input type="number" name="target_port" value="<?= $cfg['target_port'] ?>">

    Puerto Local (listen_port):
    <input type="number" name="listen_port" value="<?= $cfg['listen_port'] ?>">

    <button class="btn-edit">Guardar Cambios</button>
</form>

<?php include "templates/footer.php"; ?>
EOF

# Permisos correctos
chmod -R 755 $PANEL_DIR
chown -R www-data:www-data $PANEL_DIR

# Reiniciar Apache
systemctl restart apache2

echo "==============================================="
echo " PANEL MULTIPROXY INSTALADO EN:"
echo "   http://TU-IP/multiproxy/"
echo "==============================================="
