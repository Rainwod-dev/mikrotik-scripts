# MikroTik hAP ac³: LAN por Proton WireGuard con portal cautivo

Configuración complementaria para **RouterOS 7.20.8**. Está pensada para conservar la configuración predeterminada del hAP ac³: `ether1` como WAN y `bridge` como LAN (Wi‑Fi y `ether2`–`ether5`). No borra ni reemplaza la configuración existente.

**Este script no crea el punto de acceso Wi‑Fi.** Usa el Wi‑Fi que ya tenga
configurado el router y lo enruta por la VPN siempre que sus interfaces formen
parte de `bridge`. Se evita modificarlo automáticamente porque el hAP ac³ puede
usar el paquete `wireless` o `wifi-qcom-ac`, cuyos comandos son diferentes.

`REEMPLAZAR_CLAVE_PRIVADA` **no es la contraseña del punto de acceso**. Es el
valor `PrivateKey` de la sección `[Interface]` del archivo WireGuard entregado
por Proton. La contraseña Wi‑Fi es un valor independiente que debe elegir el
administrador.

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
2. Confirme que Wi‑Fi y `ether2`–`ether5` pertenecen a `bridge` y que `ether1` es la WAN.
3. Confirme que la puerta de enlace ADSL sea `192.168.1.1` con `/ip route print where dst-address=0.0.0.0/0`.
4. Confirme que `secure.etecsa.net` continúe resolviendo a `10.180.0.30` con `:put [:resolve secure.etecsa.net]`.
5. Edite `proton-wireguard-captive-portal.rsc` y sustituya únicamente `REEMPLAZAR_CLAVE_PRIVADA` por el valor `PrivateKey` entregado por Proton.

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
- [Policy Routing](https://help.mikrotik.com/docs/spaces/ROS/pages/59965508/Policy%2BRouting)
- [First Time Configuration](https://help.mikrotik.com/docs/spaces/ROS/pages/328151/First%2BTime%2BConfiguration)
- [DNS](https://help.mikrotik.com/docs/spaces/ROS/pages/37748767/DNS)
- [Mangle / MSS](https://help.mikrotik.com/docs/spaces/ROS/pages/48660587/Mangle)
