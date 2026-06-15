# MikroTik hAP ac³: LAN por Proton WireGuard con portal cautivo

Configuración complementaria para **RouterOS 7.20.8**. Usa `ether1` como WAN y
el `bridge1` mostrado en la configuración suministrada como LAN (`wlan1`,
`wlan2` y `ether2`–`ether5`).

El script configura `wlan1` y `wlan2` como puntos de acceso con el SSID
**`TIK-CASA`**, usando el paquete legacy `wireless` que corresponde a los nombres
de interfaz mostrados. Ambas radios usan la misma contraseña WPA2 y permanecen
dentro de `bridge1`.

`REEMPLAZAR_CLAVE_PRIVADA` **no es la contraseña del punto de acceso**. Es el
valor `PrivateKey` de la sección `[Interface]` del archivo WireGuard entregado
por Proton. `REEMPLAZAR_CLAVE_WIFI` es la contraseña WPA2 que debe elegir para
la red `TIK-CASA`; use al menos ocho caracteres.

El texto Base64 largo que Proton muestra como encabezado de la configuración
**no debe copiarse como `PrivateKey`**. Si el archivo descargado contiene
literalmente `PrivateKey = *****`, esa configuración no sirve para configurar
RouterOS: los asteriscos no son una clave válida y no existe forma de recuperar
la clave privada a partir del encabezado o de la clave pública del peer.

Elimine esa configuración en Proton y genere una nueva siguiendo el
procedimiento oficial: **Downloads → WireGuard configuration → Create → Download**.
Abra el `.conf` recién descargado con un editor de texto. Solo continúe si la
línea `PrivateKey =` contiene una cadena Base64 real y no asteriscos. No publique,
envíe ni coloque esa clave privada en el repositorio; introdúzcala únicamente en
la copia del `.rsc` que vaya a importar al router. Si una configuración recién
creada también se descarga con asteriscos, deténgase y contacte al soporte de
Proton porque el túnel no podrá autenticarse.

## ¿Está listo para importar?

No está listo mientras conserve cualquier marcador `REEMPLAZAR_*`. Antes de
ejecutarlo, también deben cumplirse todas estas condiciones:

- El router debe tener una dirección de `192.168.1.0/24` en `ether1` y debe
  alcanzar `192.168.1.1`. Compruébelo con `/ping 192.168.1.1`.
- Deben existir `bridge1`, `wlan1` y `wlan2`; las radios y `ether2`–`ether5`
  deben pertenecer a `bridge1`.
- No deben existir objetos llamados `tik-casa-security`, `proton-wg` o
  `to-proton`, porque el archivo está diseñado para una primera importación.
- Debe realizarse un respaldo y conviene importar desde una conexión por cable
  o mediante MAC-WinBox.

Este repositorio no contiene una rama local llamada `main`; la configuración
revisada está en la rama de trabajo actual.

La clave privada compartida en una conversación, incidencia, captura o
repositorio debe considerarse comprometida: elimine inmediatamente esa
configuración en Proton y genere otra. Después copie desde la nueva configuración
`PrivateKey`, `PublicKey` y la IP de `Endpoint` en los marcadores correspondientes
de su copia local. El endpoint debe sustituirse en sus **dos** apariciones: peer
y ruta directa. Nunca confirme una clave privada real en este repositorio.

## Diseño

- El router alcanza el endpoint WireGuard y el portal cautivo por la tabla `main` (ADSL).
- Después de autenticar manualmente en `https://secure.etecsa.net:8443/`, el tráfico IPv4 originado por la LAN usa exclusivamente la tabla `to-proton` y sale por `proton-wg`.
- `lookup-only-in-table` funciona como *kill switch*: si la VPN no tiene ruta utilizable, los clientes LAN no salen directamente por el ADSL.
- El ejemplo configura solo IPv4. No se anuncia IPv6 a la LAN, evitando una posible fuga IPv6. No agregue `::/0` hasta configurar firewall, enrutamiento y delegación IPv6 de extremo a extremo.

## Antes de importar

1. Conéctese por cable/MAC-WinBox y cree un respaldo:
   ```routeros
   /system backup save name=antes-proton
   /export file=antes-proton
   ```
2. Confirme que Wi‑Fi y `ether2`–`ether5` continúan perteneciendo a `bridge1` y que `ether1` es la WAN.
3. Confirme que la puerta de enlace ADSL sea `192.168.1.1` con `/ip route print where dst-address=0.0.0.0/0`.
4. Confirme que `secure.etecsa.net` continúe resolviendo a `10.180.0.30` con `:put [:resolve secure.etecsa.net]`.
5. Edite `proton-wireguard-captive-portal.rsc`: sustituya `REEMPLAZAR_CLAVE_PRIVADA`, `REEMPLAZAR_PUBLIC_KEY_PROTON`, las dos apariciones de `REEMPLAZAR_ENDPOINT_PROTON` y `REEMPLAZAR_CLAVE_WIFI` usando una configuración Proton nueva y no compartida.


El archivo ya usa la puerta de enlace ADSL `192.168.1.1` y la IP del portal
`10.180.0.30`. La excepción del portal debe ser por **dirección IP**, porque las
decisiones de ruta no usan el nombre/SNI HTTPS. Si ETECSA cambia la IP,
actualice la ruta y la regla antes de poder iniciar sesión nuevamente.

## Instalación y autenticación

Importe el archivo editado:

```routeros
/import file-name=proton-wireguard-captive-portal.rsc verbose=yes
```

Al arrancar sin sesión del ISP, abra `https://secure.etecsa.net:8443/` desde cualquier equipo de la LAN. Esa IP está exceptuada hacia ADSL; el resto queda bloqueado por el *kill switch* hasta que WireGuard pueda conectarse. Complete manualmente el inicio de sesión. El túnel debería negociar después de que el ISP habilite Internet.

## Verificación

```routeros
/interface/wireguard/peers/print detail
/ip/route/print detail where routing-table=to-proton
/routing/rule/print detail
/ip/firewall/nat/print detail where comment~"Proton"
```

Debe aumentar `last-handshake`/`rx`/`tx` del peer. Desde un cliente LAN, compruebe la IP pública. También pruebe cerrar la sesión del portal: salvo el propio portal, la LAN no debe tener salida directa.

## Notas operativas

- Proton entrega `10.2.0.1` como DNS dentro del túnel. El archivo configura el router para consultarlo y atender a la LAN. Antes de levantar la VPN, la resolución DNS general no funcionará; la URL del portal seguirá funcionando únicamente si el navegador ya conoce/resuelve su IP mediante el mecanismo del ISP. Si el portal exige DNS antes de autenticarse, conserve temporalmente el DNS del ISP y tenga presente que eso constituye una salida fuera de la VPN.
- FastTrack puede interferir con el enrutamiento por política. Para máxima previsibilidad, deshabilite la regla FastTrack predeterminada antes de probar: `/ip firewall filter disable [find where action=fasttrack-connection]`.
- Si la WAN obtiene una puerta de enlace distinta, actualice las dos rutas comentadas como `ADSL directo`.

## Documentación oficial consultada

- [WireGuard](https://help.mikrotik.com/docs/spaces/ROS/pages/69664792/WireGuard)
- [Proton VPN: descargar configuraciones WireGuard](https://protonvpn.com/support/wireguard-configurations)
- [Wireless Interface](https://help.mikrotik.com/docs/spaces/ROS/pages/8978446/Wireless%2BInterface)
- [Policy Routing](https://help.mikrotik.com/docs/spaces/ROS/pages/59965508/Policy%2BRouting)
- [First Time Configuration](https://help.mikrotik.com/docs/spaces/ROS/pages/328151/First%2BTime%2BConfiguration)
- [DNS](https://help.mikrotik.com/docs/spaces/ROS/pages/37748767/DNS)
- [Mangle / MSS](https://help.mikrotik.com/docs/spaces/ROS/pages/48660587/Mangle)
