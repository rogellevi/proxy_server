#!/bin/bash

# Variables
SCRIPT_PATH="/opt/proxy_server"
SERVICE_NAME="proxy_service"
PYTHON_SCRIPT="proxy_server.py"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

# Función para instalar dependencias
install_dependencies() {
    echo "Instalando dependencias necesarias..."
    sudo apt update
    sudo apt install -y python3-pip python3-flask python3-requests
}

# Función para crear el script de Python
create_python_script() {
    echo "Creando el script Python para el servidor proxy..."
    sudo mkdir -p ${SCRIPT_PATH}
    
    cat > ${SCRIPT_PATH}/${PYTHON_SCRIPT} <<EOL
import os
import sys

def start_proxy_service():
    """Inicia el servicio proxy con systemd."""
    os.system("sudo systemctl start proxy_service.service")
    print("Servicio proxy iniciado.")

def stop_proxy_service():
    """Detiene el servicio proxy con systemd."""
    os.system("sudo systemctl stop proxy_service.service")
    print("Servicio proxy detenido.")

def enable_proxy_service():
    """Habilita el servicio proxy para que inicie automáticamente al arrancar el sistema."""
    os.system("sudo systemctl enable proxy_service.service")
    print("Servicio proxy habilitado para iniciar al arrancar el sistema.")

def disable_proxy_service():
    """Deshabilita el servicio proxy para que no inicie automáticamente al arrancar el sistema."""
    os.system("sudo systemctl disable proxy_service.service")
    print("Servicio proxy deshabilitado al arrancar el sistema.")

def remove_proxy_service():
    """Elimina el archivo del servicio y lo detiene."""
    os.system("sudo systemctl stop proxy_service.service")
    os.system("sudo systemctl disable proxy_service.service")
    os.system("sudo rm /etc/systemd/system/proxy_service.service")
    os.system("sudo systemctl daemon-reload")
    print("Servicio proxy eliminado y deshabilitado.")

def main_menu():
    """Muestra el menú interactivo y permite al usuario seleccionar una opción."""
    while True:
        print("\\n--- Menú de administración del servicio proxy ---")
        print("1. Iniciar el servicio proxy")
        print("2. Detener el servicio proxy")
        print("3. Habilitar el servicio para iniciar al reiniciar")
        print("4. Deshabilitar el servicio al reiniciar")
        print("5. Eliminar el servicio proxy")
        print("6. Salir")
        
        try:
            option = int(input("Selecciona una opción (1-6): "))
            if option == 1:
                start_proxy_service()
            elif option == 2:
                stop_proxy_service()
            elif option == 3:
                enable_proxy_service()
            elif option == 4:
                disable_proxy_service()
            elif option == 5:
                remove_proxy_service()
            elif option == 6:
                print("Saliendo...")
                sys.exit()
            else:
                print("Opción no válida, por favor elige una opción entre 1 y 6.")
        except ValueError:
            print("Por favor ingresa un número válido.")

if __name__ == "__main__":
    main_menu()
EOL
    echo "Script Python creado en ${SCRIPT_PATH}/${PYTHON_SCRIPT}"
}

# Función para crear el archivo del servicio systemd
create_systemd_service() {
    echo "Creando el archivo de servicio systemd..."
    
    cat > ${SERVICE_PATH} <<EOL
[Unit]
Description=Servidor Proxy en Python
After=network.target

[Service]
ExecStart=/usr/bin/python3 ${SCRIPT_PATH}/${PYTHON_SCRIPT}
WorkingDirectory=${SCRIPT_PATH}
Restart=always
User=ubuntu
Group=ubuntu
Environment=PATH=/usr/bin:/usr/local/bin
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOL
    sudo systemctl daemon-reload
    echo "Servicio systemd creado en ${SERVICE_PATH}"
}

# Función para habilitar y arrancar el servicio
enable_and_start_service() {
    echo "Habilitando y arrancando el servicio proxy..."
    sudo systemctl enable ${SERVICE_NAME}.service
    sudo systemctl start ${SERVICE_NAME}.service
    echo "Servicio proxy habilitado y arrancado."
}

# Menú principal
main() {
    # Instalar dependencias
    install_dependencies
    
    # Crear el script de Python
    create_python_script
    
    # Crear el servicio systemd
    create_systemd_service
    
    # Habilitar y arrancar el servicio
    enable_and_start_service

    echo "El proceso de instalación ha finalizado con éxito."
    echo "Puedes gestionar el servicio usando el menú en el script Python."
    echo "Ejecuta 'sudo python3 /opt/proxy_server/proxy_server.py' para gestionar el servicio."
}

# Ejecutar el script
main
