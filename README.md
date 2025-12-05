¿QUÉ HACE ESTE INSTALADOR?

✔ Pide target_host y target_port.
✔ Crea /opt/proxyserver/ con:

proxy_server.py

config.txt
✔ Crea un servicio systemd para ejecutarlo siempre.
✔ Lo inicia de inmediato.
✔ Lo habilita para reinicios automáticos.


### INSTALACION

```
bash -c "$(wget -O - https://raw.githubusercontent.com/rogellevi/proxy_server/main/proxy_server.sh)"
```

```
bash -c "$(wget -O - https://raw.githubusercontent.com/rogellevi/proxy_server/main/instalar_multi_proxy.sh)"
```


### Ejecutar
```
sudo bash instalar_multi_proxy.sh
```
