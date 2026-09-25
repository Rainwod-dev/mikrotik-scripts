# Despliegue canónico del hAP ac3 — RouterOS 7.20.8

## Estado y alcance

Este paquete está diseñado exclusivamente para el **MikroTik hAP ac3
RBD53iG-5HacD2HnD con RouterOS 7.20.8**. El export recibido sólo contiene la
configuración de `wlan1`, `wlan2` y el perfil inalámbrico predeterminado; el
script conserva esos elementos y no conecta Wi-Fi silenciosamente a ninguna
LAN.

El archivo [`hap-ac3-routeros-7.20.8.rsc`](hap-ac3-routeros-7.20.8.rsc) es una
plantilla ejecutable con guardas: **aborta antes del primer cambio** mientras
falte cualquiera de estos datos:

1. puerto físico de Starlink;
2. puerto físico de ADSL;
3. puerto físico hacia OmniTik;
4. IP o red de administración confiable.

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
  `LAN_OMNITIK`, `192.168.88.1/24` y la ruta predeterminada ADSL mediante
  `192.168.1.1`.
- **`vrf-starlink`:** contiene únicamente `WAN_STARLINK`. El cliente DHCP
  instala en esta VRF la dirección, ruta conectada y ruta predeterminada de
  Starlink, evitando el conflicto con el `192.168.1.0/24` de ADSL.
- **Retorno desde Starlink:** cada cliente ADSL autorizado exige una ruta `/32`
  desde `vrf-starlink` hacia `LAN_ADSL@main`; `192.168.88.0/24` tiene una fuga
  explícita hacia `LAN_OMNITIK@main`.
- **Odoo:** se mantiene en la tabla principal y no coincide con ninguna regla
  NAT. El servidor devuelve `192.168.88.0/24` por `192.168.1.254`.
- **DHCP:** `DHCP_OMNITIK` es `static-only`, añade ARP y la interfaz usa
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

La documentación actual también indica que seleccionar la VRF en la que DNS
escucha está disponible desde RouterOS 7.21. Por eso, en 7.20.8, el DNS del hAP
permanece en `main`; sólo su salida upstream usa la ruta ADSL de `main`.

## Requisitos previos y supuestos

1. Confirmar que el equipo sigue ejecutando exactamente RouterOS 7.20.8.
2. Obtener otro `/export hide-sensitive` inmediatamente antes del cambio y
   comparar que no aparecieron configuraciones nuevas.
3. Identificar físicamente los tres puertos con `/interface ethernet print`.
4. Confirmar una estación de administración con IP fija y conexión por cable.
5. Mantener acceso físico al hAP y conocer el procedimiento Netinstall/reset.
6. Confirmar que Starlink y ADSL continúan en `192.168.1.0/24` con gateway
   `192.168.1.1`.
7. Confirmar que no se requiere incorporar `wlan1` o `wlan2` al segmento
   administrado. Este diseño las conserva, pero no las habilita como vía de
   acceso.

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

1. Copie el `.rsc` y edite las cuatro variables de `PHASE 0`.
2. Descomente y duplique las parejas de concesión/lista para todos los equipos
   OmniTik. No reutilice direcciones.
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
4. Conecte su puerto bridge al puerto hAP elegido como `LAN_OMNITIK`.

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
6. **IP visible en Odoo:** el log debe mostrar `192.168.88.x`, nunca
   `192.168.1.254`.
7. **Dominio forzado:** vacíe caché DNS, resuelva mediante `192.168.88.1`, revise
   `FORCE_ADSL` y observe aumentar la regla NAT ADSL sólo para clientes OmniTik.
8. **Solapamiento:** confirme las dos rutas conectadas en tablas distintas y
   ausencia de bridge físico entre WAN y ADSL.
9. **Persistencia:** reinicie en una ventana controlada y repita las consultas
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
