# MikroTik hAP ac³: LAN por Proton WireGuard con portal cautivo

Configuración complementaria para **RouterOS 7.20.8**. Usa `ether1` como WAN y
el `bridge1` mostrado en la configuración suministrada como LAN (`wlan1`,
`wlan2` y `ether2`–`ether5`).

El script configura `wlan1` y `wlan2` como puntos de acceso con el SSID
**`TIK-CASA`**, usando el paquete legacy `wireless` que corresponde a los nombres
de interfaz mostrados. Ambas radios usan la misma contraseña WPA2 y permanecen
dentro de `bridge1`. También configura la LAN `192.168.88.0/24`, el gateway
`192.168.88.1` y DHCP para entregar direcciones `192.168.88.10-192.168.88.254`.

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
  alcanzar `192.168.1.1`. El script asigna `192.168.1.2/24`; confirme antes que
  esa dirección está libre y compruébelo después con `/ping 192.168.1.1`.
- Deben existir `bridge1`, `wlan1` y `wlan2`; las radios y `ether2`–`ether5`
  deben pertenecer a `bridge1`.
- No deben existir objetos llamados `tik-casa-security`, `proton-wg` o
  `to-proton`, `tik-casa-pool` o `tik-casa-dhcp`, porque el archivo está diseñado
  para una primera importación.
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
3. Confirme que `192.168.1.2` esté libre y que la puerta de enlace ADSL sea `192.168.1.1`. El script asignará `192.168.1.2/24` a `ether1`.
4. Confirme que `secure.etecsa.net` continúe resolviendo a `10.180.0.30` con `:put [:resolve secure.etecsa.net]`.
5. Edite `proton-wireguard-captive-portal.rsc`: sustituya `REEMPLAZAR_CLAVE_PRIVADA`, `REEMPLAZAR_PUBLIC_KEY_PROTON`, las dos apariciones de `REEMPLAZAR_ENDPOINT_PROTON` y `REEMPLAZAR_CLAVE_WIFI` usando una configuración Proton nueva y no compartida.

El archivo ya usa la puerta de enlace ADSL `192.168.1.1` y la IP del portal
`10.180.0.30`. La excepción del portal debe ser por **dirección IP**, porque las
decisiones de ruta no usan el nombre/SNI HTTPS. Si ETECSA cambia la IP,
actualice la ruta y la regla antes de poder iniciar sesión nuevamente.

La ruta hacia `192.168.1.1` solo puede resolverse si `ether1` tiene una dirección
de la misma subred. Por eso el script configura `192.168.1.2/24` en `ether1`.
También añade NAT únicamente para el tráfico LAN dirigido al portal cautivo.
Si el módem entrega la dirección WAN mediante DHCP, no añada la dirección
estática: elimine esa línea del script y use `/ip dhcp-client add
interface=ether1 add-default-route=yes use-peer-dns=no disabled=no`.

Para reparar una instalación ya importada que no tenga dirección WAN, después
de confirmar que `192.168.1.2` está libre ejecute:

```routeros
/ip address add address=192.168.1.2/24 interface=ether1 comment="WAN hacia gateway ADSL"
/ip firewall nat add chain=srcnat dst-address=10.180.0.30 out-interface=ether1 action=masquerade comment="Portal ETECSA por ADSL"
/ping 192.168.1.1 count=4
/ping 10.180.0.30 count=4
```

## Instalación y autenticación

Importe el archivo editado:

```routeros
/import file-name=proton-wireguard-captive-portal.rsc verbose=yes
```

Al arrancar sin sesión del ISP, abra `https://secure.etecsa.net:8443/` desde cualquier equipo de la LAN. Esa IP está exceptuada hacia ADSL; el resto queda bloqueado por el *kill switch* hasta que WireGuard pueda conectarse. Complete manualmente el inicio de sesión. El túnel debería negociar después de que el ISP habilite Internet.

El script añade una entrada DNS estática para `secure.etecsa.net`, porque el DNS
de Proton `10.2.0.1` no es alcanzable antes de levantar el túnel.

## Verificación

```routeros
/interface/wireguard/peers/print detail
/ip/route/print detail where routing-table=to-proton
/routing/rule/print detail
/ip/firewall/nat/print detail where comment~"Proton"
```

Debe aumentar `last-handshake`/`rx`/`tx` del peer. Desde un cliente LAN, compruebe la IP pública. También pruebe cerrar la sesión del portal: salvo el propio portal, la LAN no debe tener salida directa.

## Diagnóstico cuando Wi-Fi o WireGuard no funcionan

Una ruta `to-proton` marcada como activa solo confirma que RouterOS acepta
`proton-wg` como gateway; **no confirma un handshake**. Un peer con
`current-endpoint-port=0`, sin `last-handshake` y con `rx=0 tx=0` todavía no ha
contactado a Proton. Primero debe autenticarse en el portal cautivo.

Ejecute este bloque y revise/comparta la salida, ocultando claves privadas y
contraseñas:

```routeros
/interface wireless print detail without-paging
/interface wireless registration-table print detail without-paging
/interface wireless security-profiles print detail without-paging
/interface bridge port print detail without-paging
/ip dhcp-server print detail without-paging
/ip dhcp-server lease print detail without-paging
/log print without-paging where topics~"wireless|wireguard|route|dns"
/ip address print detail without-paging
/ip route print detail without-paging
/ping 192.168.1.1 count=4
/ping 10.180.0.30 count=4
/ip dns static print detail where name="secure.etecsa.net"
/interface wireguard peers print detail without-paging
```

Para Wi-Fi, `wlan1` y `wlan2` deben mostrar las banderas `R` (*running*) y no
`I` (*inactive*). Si no aparecen `R`, la salida detallada y el log permiten
determinar si falta país/frecuencia, si la radio está deshabilitada o si falla
la autenticación WPA2. No cambie bandas o frecuencias a ciegas.

Si el SSID aparece y el dispositivo acepta la contraseña, pero queda en
“obteniendo dirección IP” o informa que no puede conectarse, compruebe que
`bridge1` tenga `192.168.88.1/24` y que exista un servidor DHCP activo. Para
reparar una instalación que no tenga LAN/DHCP, ejecute una sola vez:

```routeros
/interface wireless security-profiles set [find where name=tik-casa-security] authentication-types=wpa2-psk unicast-ciphers=aes-ccm group-ciphers=aes-ccm wpa2-pre-shared-key="SU_CLAVE_WIFI"
/ip address add address=192.168.88.1/24 interface=bridge1 comment="Gateway LAN TIK-CASA"
/ip pool add name=tik-casa-pool ranges=192.168.88.10-192.168.88.254
/ip dhcp-server add name=tik-casa-dhcp interface=bridge1 address-pool=tik-casa-pool disabled=no
/ip dhcp-server network add address=192.168.88.0/24 gateway=192.168.88.1 dns-server=192.168.88.1 comment="LAN TIK-CASA"
```

No vuelva a ejecutar los comandos `add` si esos objetos ya existen. Después,
olvide la red guardada en el dispositivo cliente, vuelva a conectarse y confirme
que recibe una dirección `192.168.88.x`.

Si `/ip dhcp-server print` muestra la bandera `I` (*invalid*) y
`/ip dhcp-server lease print` está vacío, los clientes se asocian al Wi-Fi pero
no reciben configuración IP; por eso muestran “sin Internet”. No diagnostique
todavía DNS ni la VPN. Primero obtenga el motivo exacto:

```routeros
/interface bridge print detail without-paging
/interface bridge port print detail without-paging
/ip pool print detail where name="tik-casa-pool"
/ip dhcp-server print detail without-paging
/ip dhcp-server network print detail without-paging
/log print without-paging where topics~"dhcp|error"
/ip dhcp-server enable [find where name="tik-casa-dhcp"]
```

El último comando puede devolver directamente el motivo de invalidez. Confirme
que `bridge1` exista, esté `R` (*running*), no sea puerto esclavo de otro bridge,
tenga `192.168.88.1/24`, y que `wlan1`, `wlan2` y `ether2`–`ether5` sean puertos
de `bridge1`. Si todo eso es correcto, recree únicamente el servidor DHCP:

```routeros
/ip dhcp-server remove [find where name="tik-casa-dhcp"]
/ip dhcp-server add name=tik-casa-dhcp interface=bridge1 address-pool=tik-casa-pool lease-time=1h authoritative=yes disabled=no
```

Desconecte y reconecte un cliente. Antes de continuar, el servidor debe perder
la bandera `I` y `/ip dhcp-server lease print` debe mostrar una concesión
`192.168.88.x`.

Cuando exista una concesión, pruebe en este orden desde RouterOS:

```routeros
/ping 10.2.0.1 count=4
/tool ping address=1.1.1.1 routing-table=to-proton count=4
/resolve example.com server=10.2.0.1
```

Si `10.2.0.1` o `1.1.1.1` falla aunque WireGuard tenga un handshake reciente,
revise contadores de NAT, reglas de firewall y rutas. Si ambos pings funcionan
pero el cliente indica “sin Internet”, revise DNS y confirme que el cliente
recibió `192.168.88.1` como gateway y DNS.

Si DHCP entrega concesiones pero `/ping 10.2.0.1` devuelve `no route to host`,
falta la ruta para que las consultas DNS originadas por el propio router entren
al túnel. Añádala y repita las pruebas:

```routeros
/ip route add dst-address=10.2.0.1/32 gateway=proton-wg routing-table=main comment="DNS Proton para el router"
/ping 10.2.0.1 count=4
/tool ping address=1.1.1.1 routing-table=to-proton count=4
/resolve google.com server=10.2.0.1
```

La ruta por defecto de `to-proton` sirve para clientes LAN afectados por la
regla de política, pero no para consultas DNS originadas por el router, que usan
la tabla `main`. Por eso se requiere la ruta `/32` adicional a `10.2.0.1`.

En RouterOS 7.20.8 use `/tool ping` —no el alias corto `/ping`— cuando necesite
el parámetro `routing-table`; el alias puede devolver `expected end of command`.

### Validación final de una instalación funcional

La instalación está operativa cuando se cumplen simultáneamente estas señales:

- `proton-wg` tiene `last-handshake` reciente y aumentan `rx`/`tx`.
- La regla NAT `Proton: NAT LAN` aumenta bytes/paquetes al navegar.
- La regla `LAN solo por Proton` está activa.
- DHCP tiene concesiones `bound` dentro de `192.168.88.0/24`.
- `/ping 10.2.0.1` responde y los clientes tienen Internet.

Como prueba del *kill switch*, deshabilite temporalmente el peer solo durante
una ventana de mantenimiento: los clientes deben perder Internet y conservar
acceso al portal ETECSA. Vuelva a habilitarlo inmediatamente:

```routeros
/interface wireguard peers disable [find where interface=proton-wg]
/interface wireguard peers enable [find where interface=proton-wg]
```

Para WireGuard, confirme primero que `/ping 192.168.1.1` y
`/ping 10.180.0.30` funcionan, abra el portal, inicie sesión y luego vuelva a
consultar el peer. Tras autenticar, debe aparecer `last-handshake` y contadores
`rx`/`tx` distintos de cero.

### Gateway ADSL accesible, pero WireGuard sigue en `rx=0 tx=0`

Si el gateway y el portal responden, pero el peer conserva
`current-endpoint-port=0`, revise que exista una ruta `/32` activa hacia el
endpoint de Proton por `192.168.1.1`. La ruta del portal no sirve para alcanzar
el endpoint de Proton. Por ejemplo, para un endpoint `84.20.27.50:51820`:

```routeros
/ip route add dst-address=84.20.27.50/32 gateway=192.168.1.1 routing-table=main comment="ADSL directo: endpoint Proton"
/interface wireguard peers set [find where interface=proton-wg] endpoint-address=84.20.27.50 endpoint-port=51820
/ping 84.20.27.50 count=4
/interface wireguard peers print detail without-paging
```

Sustituya `84.20.27.50` por la IP de la configuración Proton vigente. En
`endpoint-address` coloque solo la IP; el puerto pertenece a `endpoint-port`.
Que el ping al endpoint no responda no prueba por sí solo un fallo, porque el
servidor puede bloquear ICMP; la prueba concluyente es que aparezca
`last-handshake`. En la lista de rutas deben existir separadamente la ruta del
portal y la ruta `/32` del endpoint.

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
