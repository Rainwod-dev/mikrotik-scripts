# RouterOS 7.20.8 - complemento sobre la configuracion predeterminada
# EDITE REEMPLAZAR_CLAVE_PRIVADA y REEMPLAZAR_CLAVE_WIFI antes de importar.
# No es la clave Wi-Fi: es PrivateKey del archivo WireGuard entregado por Proton.

# Punto de acceso para el paquete legacy "wireless" mostrado por wlan1/wlan2.
# Ambas radios ya pertenecen a bridge1; no se vuelven a agregar al bridge.
/interface wireless security-profiles
add name=tik-casa-security mode=dynamic-keys authentication-types=wpa2-psk \
    wpa2-pre-shared-key="REEMPLAZAR_CLAVE_WIFI" supplicant-identity=MikroTik

/interface wireless
set [find default-name=wlan1] mode=ap-bridge ssid="TIK-CASA" \
    security-profile=tik-casa-security disabled=no
set [find default-name=wlan2] mode=ap-bridge ssid="TIK-CASA" \
    security-profile=tik-casa-security disabled=no

/interface wireguard
add name=proton-wg mtu=1420 private-key="4oKEJRIJRCgFDyIl2FhYQlDTgd2mEmH9tFizWsss/uaXj3nAmL1/HMa4jEbR8nkp6t3GcSm4ei7ELUoGWKLVgA==" comment="Proton WireGuard"

/ip address
add address=10.2.0.2/32 interface=proton-wg comment="Proton IPv4"

/interface wireguard peers
add interface=proton-wg public-key="uK67VRNOHFP8JwJRqGdZ8Ax9Pu0M7ZGnHJ+DNq4TFiM=" endpoint-address=84.20.27.51 endpoint-port=51820 allowed-address=0.0.0.0/0 persistent-keepalive=25s comment="Proton MX-FREE#15"

/routing table
add fib name=to-proton

# Evitan que el endpoint VPN y el portal cautivo intenten cruzar el propio tunel.
/ip route
add dst-address=84.20.27.51/32 gateway=192.168.1.1 routing-table=main comment="ADSL directo: endpoint Proton"
add dst-address=10.180.0.30/32 gateway=192.168.1.1 routing-table=main comment="ADSL directo: portal ETECSA"
add dst-address=0.0.0.0/0 gateway=proton-wg routing-table=to-proton comment="Default LAN por Proton"

# La excepcion del portal debe aparecer antes de la regla LAN. La segunda regla es kill switch.
/routing rule
add dst-address=10.180.0.30/32 action=lookup-only-in-table table=main comment="Portal ETECSA por ADSL"

add interface=bridge1 action=lookup-only-in-table table=to-proton comment="LAN solo por Proton"

/ip firewall nat
add chain=srcnat out-interface=proton-wg action=masquerade comment="Proton: NAT LAN"

# Reduce problemas de PMTU en el tunel.
/ip firewall mangle
add chain=forward out-interface=proton-wg protocol=tcp tcp-flags=syn action=change-mss new-mss=clamp-to-pmtu comment="Proton: clamp MSS"

# DNS privado de Proton; el DHCP predeterminado normalmente anuncia la IP del router.
/ip dns
set servers=10.2.0.1 allow-remote-requests=yes
