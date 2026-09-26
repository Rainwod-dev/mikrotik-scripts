# Despliegue canónico del hAP ac3 — RouterOS 7.20.8

## Lista inequívoca: qué se rellena y cuándo

### Antes de importar

- Las siete variables de `PHASE 0`: IP `/32` y MAC del administrador, SSID,
  contraseña WPA2, país y las listas de puertos TCP/UDP de Odoo.
- Los dominios `FORCE_ADSL`.
- Sólo los clientes `ADSL_STARLINK` que deban funcionar desde el primer corte.

### No se rellena antes de importar

- Las IP/MAC de futuros clientes conectados mediante OmniTik, `wlan1` o
  `wlan2`. Esos equipos se descubren posteriormente en `POOL_ENROLLMENT`, se
  convierten en reservas y se asignan a `OMNI_ODOO_ONLY` o
  `OMNI_ODOO_STARLINK` siguiendo la sección de enrolamiento.

Esta separación es intencional: permite instalar el router con una identidad
administrativa segura sin exigir un inventario anticipado de todos los clientes.

## Estado y alcance

Este paquete está diseñado exclusivamente para el **MikroTik hAP ac3
RBD53iG-5HacD2HnD con RouterOS 7.20.8**. El export recibido sólo contiene la
configuración mínima de `wlan1`, `wlan2` y el perfil inalámbrico predeterminado.
El script configura ambas radios como AP, con WPA2-AES, y las incorpora junto
con OmniTik al segmento administrado `192.168.88.0/24`.

El archivo [`hap-ac3-routeros-7.20.8.rsc`](hap-ac3-routeros-7.20.8.rsc) es una
plantilla ejecutable con guardas: **aborta antes del primer cambio** si el
equipo no es un `hAP ac^3`, si la versión no es exactamente `7.20.8`, si no
existen las interfaces esperadas, si falta cualquiera de los primeros cinco
datos o si no se define ningún puerto de Odoo:

1. IP `/32` del equipo administrador;
2. MAC del equipo administrador;
3. SSID inalámbrico;
4. contraseña WPA2 de 8 a 63 caracteres;
5. país reglamentario para las radios;
6. puertos TCP de Odoo, si utiliza TCP;
7. puertos UDP de Odoo, si utiliza UDP.

Debe completarse al menos una de las dos variables de puertos de Odoo. Las
guardas no pueden comprobar los valores que permanecen como líneas comentadas
(dominios y altas `ADSL_STARLINK`), cuya revisión manual sigue siendo
obligatoria.

## Dictamen de revisión antes del despliegue

El diseño, el script y esta guía son coherentes con RouterOS **7.20.8
(long-term)** y con el `hAP ac^3` informado. Sin embargo, el archivo versionado
es deliberadamente una **plantilla y no está listo para importarse tal cual**:

- las siete variables de `PHASE 0` están vacías;
- los dominios reales `FORCE_ADSL` siguen sin definir;
- deben incorporarse los clientes `ADSL_STARLINK` necesarios para el primer
  corte, si existe alguno;
- aún se debe comparar un export inmediatamente anterior al cambio con el
  export mínimo sobre el que se preparó la plantilla;
- deben estar preparados la ruta de retorno de Odoo y el cambio de OmniTik a
  bridge/AP.

El estado pasa a **listo para proceder siguiendo la guía** únicamente cuando
todos esos puntos se hayan completado en una copia local, se hayan etiquetado y
cableado los tres puertos, se hayan descargado las copias de seguridad y el
operador disponga de acceso físico y una sesión por cable en Safe Mode. No se
deben guardar secretos ni valores de producción en este repositorio.

## Cableado obligatorio

El script usa un mapeo fijo y documentado; conecte los cables **antes de
importarlo** de esta forma:

| Puerto físico hAP | Nombre después del script | Conexión |
|---|---|---|
| `ether1` | `WAN_STARLINK` | Puerto LAN del router Starlink |
| `ether2` | `LAN_ADSL` | Switch/LAN existente del router ADSL |
| `ether3` | `LAN_OMNITIK` | Puerto bridge/uplink del OmniTik |
| `ether4`, `ether5` | sin cambios | Reservados; no forman parte de este diseño |

No intercambie `ether1` y `ether2`: ambos enlaces usan `192.168.1.0/24`, pero
solamente `ether1` entra en `vrf-starlink`. `ether3`, `wlan1` y `wlan2` pasan a
ser puertos del bridge `BR_MANAGED`.

Además, antes de desplegar se deben completar las entradas comentadas para:

- cada dispositivo `ADSL_STARLINK` que necesite estar autorizado desde el
  primer momento (IP, MAC y nombre);
- cada dominio `FORCE_ADSL`;
- los puertos TCP/UDP exactos de Odoo.

Las MAC de los futuros clientes OmniTik/Wi-Fi **no se rellenan antes de
importar**: se descubren y autorizan posteriormente mediante el pool de
enrolamiento descrito en esta guía.

No se han inventado valores de producción. No se debe importar el archivo sin
revisar y completar esos datos.

> **No basta con configurar las siete variables iniciales.** Éstas permiten una
> importación segura y acceso administrativo IP+MAC. Los dispositivos nuevos
> recibirán una dirección de cuarentena `192.168.88.200-239`, pero no tendrán
> Odoo ni Internet hasta que el administrador los registre. Antes de finalizar
> el despliegue también son obligatorios los dominios y puertos enumerados arriba.

## Arquitectura implementada

- **Tabla principal:** contiene `LAN_ADSL`, `192.168.1.254/24`,
  `BR_MANAGED`, `192.168.88.1/24` y la ruta predeterminada ADSL mediante
  `192.168.1.1`.
- **`vrf-starlink`:** contiene únicamente `WAN_STARLINK`. El cliente DHCP
  instala en esta VRF la dirección, ruta conectada y ruta predeterminada de
  Starlink, evitando el conflicto con el `192.168.1.0/24` de ADSL.
- **Retorno desde Starlink:** cada cliente ADSL autorizado exige una ruta `/32`
  desde `vrf-starlink` hacia `LAN_ADSL@main`; `192.168.88.0/24` tiene una fuga
  explícita hacia `BR_MANAGED@main`.
- **Odoo:** se mantiene en la tabla principal y no coincide con ninguna regla
  NAT. El servidor devuelve `192.168.88.0/24` por `192.168.1.254`.
- **OmniTik y Wi-Fi:** `ether3`, `wlan1` y `wlan2` pertenecen a `BR_MANAGED`.
  Los clientes inalámbricos que deban usar Odoo, Starlink y las excepciones
  ADSL se registran en `OMNI_ODOO_STARLINK`.
- **DHCP/enrolamiento:** un equipo desconocido recibe temporalmente
  `192.168.88.200-239` para que el administrador vea su MAC, pero no pertenece a
  ningún grupo y el firewall le niega forwarding. Después se convierte en lease
  estático `192.168.88.10-199` y se añade a exactamente un grupo. El servidor
  añade ARP y el bridge usa `reply-only`.
- **Política:** mangle excluye primero Odoo y `FORCE_ADSL`; después sólo marca
  para Starlink las fuentes autorizadas. El firewall aplica permisos concretos
  y denegación final.
- **DNS/dominios:** los clientes de política usan el resolvedor del hAP. Las
  entradas DNS estáticas alimentan `FORCE_ADSL` y caducan con el TTL observado.

## Fundamento en documentación oficial

La implementación fue contrastada con la documentación oficial de MikroTik:

- [VRF](https://help.mikrotik.com/docs/spaces/ROS/pages/328206/Virtual+Routing+and+Forwarding+-+VRF): orden de interfaces, tablas dinámicas,
  rutas entre VRF con `@tabla` y cambio del comportamiento de interfaces de
  firewall desde RouterOS 7.14.
- [Policy Routing](https://help.mikrotik.com/docs/spaces/ROS/pages/59965508/Policy+Routing): tablas, `mark-routing` y prioridad de mangle.
- [DNS](https://help.mikrotik.com/docs/spaces/ROS/pages/37748767/DNS):
  `address-list`, `match-subdomain` y expiración por TTL.
- [DHCP](https://help.mikrotik.com/docs/spaces/ROS/pages/24805500/DHCP): cliente
  DHCP dentro de una VRF, leases estáticos, pools y propiedades relacionadas.
- [Firewall Filter](https://help.mikrotik.com/docs/spaces/ROS/pages/48660574/Filter): estados de conexión, cadenas y acciones de filtrado.
- [Wireless Interface](https://help.mikrotik.com/docs/spaces/ROS/pages/8978446/Wireless+Interface): modo AP, país, seguridad WPA2 y parámetros de las radios legacy.
- [Bridging and Switching](https://help.mikrotik.com/docs/spaces/ROS/pages/328068/Bridging+and+Switching): bridge y pertenencia de puertos.

La documentación actual también indica que seleccionar la VRF en la que DNS
escucha está disponible desde RouterOS 7.21. Por eso, en 7.20.8, el DNS del hAP
permanece en `main`; sólo su salida upstream usa la ruta ADSL de `main`.

## Requisitos previos y supuestos

1. Confirmar que el equipo sigue ejecutando exactamente RouterOS 7.20.8.
2. Obtener otro `/export hide-sensitive` inmediatamente antes del cambio y
   comparar que no aparecieron configuraciones nuevas.
3. Etiquetar físicamente `ether1=Starlink`, `ether2=ADSL` y `ether3=OmniTik`.
4. Confirmar una estación de administración con IP fija y conexión por cable.
5. Mantener acceso físico al hAP y conocer el procedimiento Netinstall/reset.
6. Confirmar que Starlink y ADSL continúan en `192.168.1.0/24` con gateway
   `192.168.1.1`.
7. Elegir SSID, contraseña WPA2 y país reglamentario. No guarde la contraseña
   real en Git; edítela únicamente en la copia que se cargará al router.

## Preparación y copias de seguridad

Use un nombre con fecha/hora elegido por el operador, sin espacios. Ejemplo:

```routeros
/system backup save name=pre-canonical-20260925-1200 dont-encrypt=no
/export hide-sensitive file=pre-canonical-20260925-1200
/file print where name~"pre-canonical-20260925-1200"
```

Descargue ambos archivos fuera del router. El script toma además copias con el
nombre fijo `pre-canonical-7.20.8`, pero éstas no sustituyen la copia fechada.

Active **Safe Mode** (`Ctrl+X`) en una sesión cableada desde la LAN ADSL antes
de importar. No lo ejecute desde Wi-Fi, Starlink ni el enlace de OmniTik. El
script renombra `ether2` como `LAN_ADSL`; por ello mantenga abierta la sesión
original y confirme una segunda conexión administrativa antes de salir de Safe
Mode.

## Preparación del script

1. Copie el `.rsc` y edite las siete variables de `PHASE 0`. Por ejemplo, para
   que sólo el equipo `192.168.1.101` con MAC `AA:BB:CC:DD:EE:FF` administre:

   ```routeros
   :local trustedManagementIpCidr "192.168.1.101/32"
   :local trustedManagementMac "AA:BB:CC:DD:EE:FF"
   :local wifiSSID "EMPRESA"
   :local wifiPassphrase "CAMBIAR-EN-COPIA-LOCAL"
   :local wifiCountry "united states"
   :local odooTcpPorts "443,8069"
   :local odooUdpPorts ""
   ```

   Tanto IP como MAC deben coincidir para SSH, WinBox e ICMP. No use
   `192.168.1.101/24`: autorizaría el prefijo completo `192.168.1.0/24` en la
   restricción del servicio. La contraseña del ejemplo debe sustituirse y nunca
   confirmarse en Git.

   Para una instalación físicamente ubicada en Estados Unidos use exactamente:

   ```routeros
   :local wifiCountry "united states"
   ```

   El valor no es un código ISO como `US`; es el nombre que acepta el paquete
   legacy `wireless`. Puede comprobar el dominio regulatorio y los canales
   resultantes después de importarlo con:

   ```routeros
   /interface wireless info country-info country="united states"
   /interface wireless info allowed-channels wlan1
   /interface wireless info allowed-channels wlan2
   ```

   Utilice este país únicamente cuando el equipo esté físicamente en Estados
   Unidos; la selección limita canales y potencia conforme al dominio
   regulatorio.
2. No necesita conocer previamente las MAC de OmniTik/Wi-Fi. Tras importar,
   siga el procedimiento de enrolamiento de la sección siguiente.
3. Para cada equipo ADSL autorizado, descomente las cuatro líneas: lista IP,
   ruta `/32` de retorno y las dos reglas `src-address` + `src-mac-address`.
4. Descomente una entrada DNS por cada dominio. `match-subdomain=yes` cubre el
   nombre base y sus subdominios.
5. En `odooTcpPorts` y `odooUdpPorts` coloque listas RouterOS separadas por
   comas y sin espacios; también puede utilizar rangos como `8071-8072`. El
   script crea automáticamente las reglas para ambos grupos administrados antes
   de la denegación general de Odoo. Deje una variable vacía únicamente si Odoo
   no usa ese protocolo; al menos una de las dos debe contener un puerto.
6. El diseño inicial autoriza una sola pareja IP+MAC administrativa. Si necesita
   más administradores, cree para cada uno reglas input equivalentes con su
   propia IP `/32` y MAC, y añada sus `/32` al parámetro `address` de SSH y
   WinBox; no amplíe el primer administrador a `/24`.
7. Revise todo el archivo. La importación está diseñada para hacerse una sola
   vez sobre el export mínimo suministrado; no es un reconciliador idempotente.

Importe con:

```routeros
/import file-name=hap-ac3-routeros-7.20.8.rsc verbose=yes
```

Mantenga Safe Mode hasta completar las comprobaciones básicas de rutas,
administración y Odoo.

## Cómo registrar dispositivos después de importar

El pool `192.168.88.200-239` es sólo de descubrimiento. Los equipos desconocidos
pueden asociarse y obtener DHCP, pero la regla `CANONICAL: managed default deny`
les impide llegar a Odoo, ADSL o Starlink.

No necesita conocer previamente la pareja IP/MAC de todos los equipos que se
conectarán por OmniTik o por el Wi-Fi del hAP. Antes de importar sólo necesita
la pareja IP/MAC del administrador y, si deben funcionar durante el primer
corte, las parejas de los clientes `ADSL_STARLINK`. Los demás equipos se
descubren en este pool, reciben después una IP fija elegida por el administrador
y se asignan a uno de los dos grupos de política.

1. Conecte el nuevo equipo por OmniTik, `wlan1` o `wlan2`.
2. Desde la sesión administrativa IP+MAC, localice la concesión dinámica:

   ```routeros
   /ip dhcp-server lease print detail where server=DHCP_MANAGED
   ```

3. Copie su MAC, elija una IP libre de `192.168.88.10-199` y cree la reserva.
   Reemplace los valores de ejemplo:

   ```routeros
   /ip dhcp-server lease remove [find where server=DHCP_MANAGED && mac-address="AA:BB:CC:DD:EE:01"]
   /ip dhcp-server lease add server=DHCP_MANAGED mac-address=AA:BB:CC:DD:EE:01 address=192.168.88.20 comment="PC CONTABILIDAD"
   ```

4. Asigne **exactamente un** grupo:

   ```routeros
   # Odoo sin Internet
   /ip firewall address-list add list=OMNI_ODOO_ONLY address=192.168.88.20 comment="PC CONTABILIDAD"

   # O bien: Odoo + Starlink + dominios FORCE_ADSL
   /ip firewall address-list add list=OMNI_ODOO_STARLINK address=192.168.88.20 comment="PC CONTABILIDAD"
   ```

5. Renueve DHCP en el cliente y compruebe que obtiene `192.168.88.20`. Si cambia
   de grupo, elimine primero su entrada anterior para evitar doble pertenencia:

   ```routeros
   /ip firewall address-list remove [find where list=OMNI_ODOO_ONLY && address=192.168.88.20]
   ```

Para dar Starlink a un equipo que ya está en la LAN ADSL, éste debe conservar
una IP fija `192.168.1.x` y usar gateway `.254`. Añada su IP a
`ADSL_STARLINK`, una ruta `/32` en `vrf-starlink` y las dos reglas forward que
combinan esa IP con su MAC; copie y adapte las cuatro líneas de `PHASE 4` del
script. Este alta requiere una ventana de mantenimiento porque modifica reglas
activas.

## Cambios externos separados

### Servidor Odoo

Configure una ruta persistente, utilizando el mecanismo del sistema operativo:

```text
192.168.88.0/24 via 192.168.1.254
```

No configure una ruta predeterminada nueva ni NAT en Odoo. Verifique además que
el firewall del servidor permite los puertos confirmados desde
`192.168.88.0/24`.

### OmniTik

1. Conviértalo en bridge/AP, sin NAT, firewall de router ni servidor DHCP.
2. Configure administración estática `192.168.88.2/24`.
3. Configure gateway y DNS `192.168.88.1` sólo para su propio tráfico de
   gestión.
4. Conecte su puerto bridge exclusivamente a `ether3` (`LAN_OMNITIK`) del hAP.

### Clientes ADSL autorizados

Reserve/configure la IP autorizada y cambie únicamente su gateway a
`192.168.1.254`. Los clientes ADSL normales conservan `192.168.1.1`.

## Limitaciones de seguridad y DNS

- En el LAN ADSL no administrado, la pareja IP+MAC detiene el uso casual de
  `.254`, pero un atacante local puede clonar ambos valores. Esto no equivale a
  802.1X ni a control de acceso empresarial.
- Se redirige DNS clásico TCP/UDP 53. **DoH y DoT quedan fuera de alcance** y no
  se bloquean por listas de proveedores, porque hacerlo de forma completa exige
  una política adicional mantenida continuamente. Un cliente que use DNS
  cifrado puede impedir que RouterOS aprenda la IP del dominio y, por tanto,
  eludir la selección `FORCE_ADSL` (aunque no obtiene autorización Starlink si
  no pertenece a un grupo).
- Un dominio puede resolver a CDN o IP compartidas. En ese caso, la ruta se
  aplica a la IP y puede afectar tráfico de otros nombres, o cambiar cuando el
  proveedor modifique sus respuestas.
- El requisito es por dominio/IP resuelta, nunca por ruta URL HTTPS.
- IPv6 no tiene todavía un diseño de políticas equivalente. El script bloquea
  forwarding IPv6 entrante desde los segmentos de política para impedir bypass,
  sin desinstalar ni desactivar IPv6 en el router.

## Qué hacer inmediatamente después de ejecutar el script

1. Sin salir de Safe Mode, confirme que `WAN_STARLINK` tiene una concesión DHCP
   y una ruta predeterminada en `vrf-starlink`.
2. Confirme que puede volver a abrir WinBox o SSH desde la pareja
   `trustedManagementIpCidr` + `trustedManagementMac`; no cierre la sesión
   original antes de probarlo.
3. Aplique en Odoo la ruta persistente `192.168.88.0/24 via 192.168.1.254` y
   pruebe el retorno antes de continuar.
4. Convierta OmniTik a bridge/AP, quite su DHCP/NAT y conecte su uplink a
   `ether3`.
5. En cada cliente ADSL autorizado, establezca gateway `192.168.1.254` y
   compruebe que su IP/MAC coincide con las cuatro entradas del script.
6. Conecte un dispositivo registrado a cada radio. `wlan1` y `wlan2` comparten
   SSID y política; el dispositivo debe obtener únicamente su IP reservada de
   `DHCP_MANAGED`.
7. Resuelva cada dominio forzado usando `192.168.88.1` y confirme que aparecen
   direcciones dinámicas en `FORCE_ADSL`.
8. Ejecute toda la matriz de aceptación siguiente. Salga de Safe Mode sólo
   cuando administración, Odoo y ambos egresos hayan sido comprobados.

## Validación

### Estado del router

```routeros
/system resource print
/interface print detail
/ip vrf print detail
/ip dhcp-client print detail
/ip dhcp-server print detail
/ip dhcp-server lease print detail
/ip address print detail
/ip route print detail where routing-table=main
/ip route print detail where routing-table=vrf-starlink
/ip firewall address-list print detail
/ip firewall mangle print stats
/ip firewall nat print stats
/ip firewall filter print stats
```

Debe existir simultáneamente un `192.168.1.0/24` conectado a `LAN_ADSL` en
`main` y otro conectado a `WAN_STARLINK` en `vrf-starlink`. No debe existir un
bridge entre ambos.

Pruebe ambos gateways desde el router indicando tabla:

```routeros
/tool ping address=192.168.1.1 routing-table=main count=5
/tool ping address=192.168.1.1 routing-table=vrf-starlink count=5
```

### Matriz de aceptación

1. **ADSL normal:** gateway `.1`, Odoo y ADSL Internet funcionan; los contadores
   de Starlink no aumentan.
2. **ADSL no autorizado con gateway `.254`:** Odoo sigue siendo local L2, pero
   Internet por hAP falla y aumenta `DENY_ADSL_GW`.
3. **`ADSL_STARLINK`:** compruebe IP+MAC, ruta `/32`, Odoo directo, Internet por
   Starlink y dominios seleccionados por ADSL.
4. **`OMNI_ODOO_ONLY`:** obtiene sólo su concesión reservada, llega únicamente
   a los puertos aprobados de Odoo y no llega a Internet ni a otros hosts ADSL.
5. **`OMNI_ODOO_STARLINK`:** llega a Odoo, usa Starlink normalmente y ADSL sólo
   para `FORCE_ADSL`.
6. **Wi-Fi en ambas bandas:** un cliente registrado prueba primero `wlan1` y
   luego `wlan2`; en ambos casos recibe la misma reserva, llega a Odoo, usa
   Starlink para destinos generales y ADSL para `FORCE_ADSL`.
7. **IP visible en Odoo:** el log debe mostrar `192.168.88.x`, nunca
   `192.168.1.254`.
8. **Dominio forzado:** vacíe caché DNS, resuelva mediante `192.168.88.1`, revise
   `FORCE_ADSL` y observe aumentar la regla NAT ADSL sólo para clientes OmniTik.
9. **Solapamiento:** confirme las dos rutas conectadas en tablas distintas y
   ausencia de bridge físico entre WAN y ADSL.
10. **Persistencia:** reinicie en una ventana controlada y repita las consultas
   de estado y la matriz completa.

Use `traceroute`, contadores de reglas y una IP pública de diagnóstico aprobada
para distinguir los egresos; no confíe solamente en que una página cargue.

## Rollback

### Si aún está en Safe Mode

Pulse `Ctrl+X` o cierre abruptamente la sesión para que RouterOS revierta los
cambios de esa sesión. Ésta es la recuperación preferida durante el despliegue.

### Si conserva acceso administrativo

Restaure la copia binaria y reinicie:

```routeros
/system backup load name=pre-canonical-20260925-1200.backup password="CONTRASENA_DE_LA_COPIA"
```

Use el nombre real descargado. La restauración reinicia el router. Si sólo falla
Starlink, no improvise una ruta que mezcle ambos `/24`: vuelva atrás y examine
DHCP/VRF/rutas `/32`. Si falla OmniTik, desconéctelo del hAP y restaure primero
su servicio anterior antes de revertir el router.

### Si se pierde toda administración

Use acceso físico: reset controlado y restauración de la copia binaria local, o
Netinstall como último recurso. Después restaure por separado la configuración
anterior del OmniTik, la ruta del servidor Odoo y los gateways de los clientes
ADSL modificados.
