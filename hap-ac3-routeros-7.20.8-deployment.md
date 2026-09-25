# Despliegue canónico del hAP ac3 — RouterOS 7.20.8

## Estado y alcance

Este paquete está diseñado exclusivamente para el **MikroTik hAP ac3
RBD53iG-5HacD2HnD con RouterOS 7.20.8**. El export recibido sólo contiene la
configuración mínima de `wlan1`, `wlan2` y el perfil inalámbrico predeterminado.
El script configura ambas radios como AP, con WPA2-AES, y las incorpora junto
con OmniTik al segmento administrado `192.168.88.0/24`.

El archivo [`hap-ac3-routeros-7.20.8.rsc`](hap-ac3-routeros-7.20.8.rsc) es una
plantilla ejecutable con guardas: **aborta antes del primer cambio** mientras
falte cualquiera de estos datos:

1. IP o red de administración confiable;
2. SSID inalámbrico;
3. contraseña WPA2 de 8 a 63 caracteres;
4. país reglamentario para las radios.

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

- cada dispositivo `ADSL_STARLINK` (IP, MAC y nombre);
- cada dispositivo `OMNI_ODOO_ONLY` (MAC, IP fija y nombre);
- cada dispositivo `OMNI_ODOO_STARLINK` (MAC, IP fija y nombre);
- cada dominio `FORCE_ADSL`;
- los puertos TCP/UDP exactos de Odoo.

No se han inventado valores de producción. No se debe importar el archivo sin
revisar y completar esos datos.

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
- **DHCP:** `DHCP_MANAGED` es `static-only`, añade ARP y el bridge usa
  `reply-only`. Cada concesión estática tiene una pertenencia explícita a un
  grupo de firewall.
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
  DHCP dentro de una VRF, servidor `static-only` y propiedades relacionadas.
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

Active **Safe Mode** (`Ctrl+X`) en una sesión cableada antes de importar. No
ejecute el cambio desde el enlace que vaya a renombrarse o desde Wi-Fi.

## Preparación del script

1. Copie el `.rsc` y edite las cuatro variables de `PHASE 0`: red de gestión,
   SSID, contraseña WPA2 y país.
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
2. Descomente y duplique las parejas de concesión/lista para todos los equipos
   OmniTik **y Wi-Fi**. Los clientes de `wlan1`/`wlan2` que requieren Odoo,
   Starlink y dominios por ADSL deben pertenecer a `OMNI_ODOO_STARLINK`. No
   reutilice direcciones.
3. Para cada equipo ADSL autorizado, descomente las cuatro líneas: lista IP,
   ruta `/32` de retorno y las dos reglas `src-address` + `src-mac-address`.
4. Descomente una entrada DNS por cada dominio. `match-subdomain=yes` cubre el
   nombre base y sus subdominios.
5. Sustituya los ejemplos de puertos de Odoo por sus puertos reales y cree las
   reglas para ambos grupos OmniTik. Si Odoo usa UDP, cree reglas UDP separadas.
6. Añada entradas adicionales a `TRUSTED_MANAGEMENT` si hay más administradores.
7. Revise todo el archivo. La importación está diseñada para hacerse una sola
   vez sobre el export mínimo suministrado; no es un reconciliador idempotente.

Importe con:

```routeros
/import file-name=hap-ac3-routeros-7.20.8.rsc verbose=yes
```

Mantenga Safe Mode hasta completar las comprobaciones básicas de rutas,
administración y Odoo.

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
2. Confirme que puede volver a abrir WinBox o SSH desde
   `trustedManagementCidr`; no cierre la sesión original antes de probarlo.
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
