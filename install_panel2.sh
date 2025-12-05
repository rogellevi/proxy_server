#!/bin/bash

echo "==============================================="
echo " INSTALADOR DEL PANEL WEB MULTIPROXY (BOOTSTRAP LIGHT)"
echo "==============================================="

# 1. Actualizar sistema
apt update -y

# 2. Instalar Apache + PHP
apt install -y apache2 php libapache2-mod-php

# 3. Crear carpeta del panel
PANEL_DIR="/var/www/html/multiproxy"
mkdir -p $PANEL_DIR

echo "Copiando archivos del panel Bootstrap..."

# ------------------- style.css -------------------
cat <<'EOF' > $PANEL_DIR/style.css
.table td, .table th {
    vertical-align: middle;
}
.card {
    margin-bottom: 20px;
}
.btn {
    border-radius: 6px;
}
.container-custom {
    max-width: 1100px;
    margin: auto;
    padding-top: 30px;
}
EOF

# ------------------- header.php -------------------
cat <<'EOF' > $PANEL_DIR/header.php
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Panel MultiProxy</title>

    <!-- Bootstrap 5 -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">

    <link rel="stylesheet" href="style.css">
</head>

<body class="bg-light">

<nav class="navbar navbar-expand-lg navbar-light bg-white shadow-sm">
  <div class="container-fluid">
    <a class="navbar-brand fw-bold" href="/multiproxy/">MultiProxy Panel</a>
  </div>
</nav>

<div class="container container-custom">
EOF

# ------------------- footer.php -------------------
cat <<'EOF' > $PANEL_DIR/footer.php
</div>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>
EOF

# ------------------- index.php -------------------
cat <<'EOF' > $PANEL_DIR/index.php
<?php
include "header.php";

$basePath = "/opt/multiproxy/";
$proxies = [];

foreach (glob($basePath . "proxy_*") as $dir) {
    $cfg = $dir . "/config.txt";
    if (file_exists($cfg)) {
        $content = parse_ini_file($cfg);
        $id = basename($dir);
        $proxies[] = [
            "id" => str_replace("proxy_", "", $id),
            "target_host" => $content["target_host"],
            "target_port" => $content["target_port"],
            "listen_port" => $content["listen_port"],
        ];
    }
}
?>

<div class="card shadow-sm">
  <div class="card-body">
    <h3 class="card-title mb-3">Proxys configurados</h3>

    <table class="table table-striped table-bordered align-middle">
      <thead class="table-light">
        <tr>
          <th>ID</th>
          <th>Puerto Local</th>
          <th>Destino</th>
          <th width="260px">Acciones</th>
        </tr>
      </thead>
      <tbody>
        <?php foreach ($proxies as $p): ?>
        <tr>
          <td><?= $p["id"] ?></td>
          <td><span class="badge bg-primary"><?= $p["listen_port"] ?></span></td>
          <td><?= $p["target_host"] ?>:<?= $p["target_port"] ?></td>
          <td>

            <form method="POST" action="actions.php" class="d-inline">
              <input type="hidden" name="id" value="<?= $p["id"] ?>">
              <button name="action" value="start" class="btn btn-success btn-sm">Start</button>
            </form>

            <form method="POST" action="actions.php" class="d-inline">
              <input type="hidden" name="id" value="<?= $p["id"] ?>">
              <button name="action" value="stop" class="btn btn-danger btn-sm">Stop</button>
            </form>

            <a href="edit.php?id=<?= $p["id"] ?>" class="btn btn-warning btn-sm">
              Editar
            </a>

            <form method="POST" action="actions.php" class="d-inline">
              <input type="hidden" name="id" value="<?= $p["id"] ?>">
              <button name="action" value="delete" class="btn btn-outline-danger btn-sm">
                Eliminar
              </button>
            </form>

          </td>
        </tr>
        <?php endforeach; ?>
      </tbody>
    </table>
  </div>
</div>

<div class="card shadow-sm mt-4">
  <div class="card-body">
    <h3 class="card-title mb-3">Crear nuevo proxy</h3>

    <form method="POST" action="actions.php">
      <input type="hidden" name="action" value="create">

      <div class="mb-3">
        <label class="form-label">Target Host</label>
        <input type="text" name="target_host" class="form-control" required>
      </div>

      <div class="mb-3">
        <label class="form-label">Target Port</label>
        <input type="number" name="target_port" class="form-control" required>
      </div>

      <div class="mb-3">
        <label class="form-label">Puerto Local (listen_port)</label>
        <input type="number" name="listen_port" class="form-control" required>
      </div>

      <button class="btn btn-primary">Crear Proxy</button>
    </form>
  </div>
</div>

<?php include "footer.php"; ?>
EOF

# ------------------- actions.php -------------------
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
        shell_exec("systemctl start ".serviceName($id));
        break;

    case "stop":
        shell_exec("systemctl stop ".serviceName($id));
        break;

    case "delete":
        shell_exec("systemctl stop ".serviceName($id));
        shell_exec("systemctl disable ".serviceName($id));
        unlink("/etc/systemd/system/".serviceName($id));
        shell_exec("rm -rf $basePath/proxy_$id");
        shell_exec("systemctl daemon-reload");
        break;

    case "create":
        $host = $_POST["target_host"];
        $p1   = $_POST["target_port"];
        $lp   = $_POST["listen_port"];
        
        $id = count(glob($basePath."proxy_*")) + 1;
        $dir = $basePath."proxy_$id";

        mkdir($dir);

        file_put_contents("$dir/config.txt",
"target_host=$host
target_port=$p1
listen_port=$lp"
        );

        shell_exec("cp $basePath/proxy_1/proxy_server.py $dir/proxy_server.py");

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
"target_host=$host
target_port=$p1
listen_port=$lp"
        );

        shell_exec("systemctl restart ".serviceName($id));
        break;
}

header("Location: index.php");
exit;
?>
EOF

# ------------------- edit.php -------------------
cat <<'EOF' > $PANEL_DIR/edit.php
<?php
include "header.php";

$id = $_GET["id"];
$cfg = parse_ini_file("/opt/multiproxy/proxy_$id/config.txt");
?>

<div class="card shadow-sm">
  <div class="card-body">
    <h3 class="card-title">Editar Proxy <?= $id ?></h3>

    <form method="POST" action="actions.php">
      <input type="hidden" name="action" value="edit">
      <input type="hidden" name="id" value="<?= $id ?>">

      <div class="mb-3">
        <label class="form-label">Target Host</label>
        <input type="text" name="target_host" class="form-control" value="<?= $cfg['target_host'] ?>" required>
      </div>

      <div class="mb-3">
        <label class="form-label">Target Port</label>
        <input type="number" name="target_port" class="form-control" value="<?= $cfg['target_port'] ?>" required>
      </div>

      <div class="mb-3">
        <label class="form-label">Puerto Local (listen_port)</label>
        <input type="number" name="listen_port" class="form-control" value="<?= $cfg['listen_port'] ?>" required>
      </div>

      <button class="btn btn-warning">Guardar Cambios</button>
    </form>
  </div>
</div>

<?php include "footer.php"; ?>
EOF

# Permisos correctos
chown -R www-data:www-data $PANEL_DIR
chmod -R 755 $PANEL_DIR

# Reiniciar Apache
systemctl restart apache2

echo "==============================================="
echo " PANEL MULTIPROXY (Bootstrap Light) INSTALADO"
echo " URL: http://TU-IP/multiproxy/"
echo "==============================================="
