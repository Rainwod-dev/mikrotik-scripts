# RouterOS 7.20.8 - complemento sobre la configuracion predeterminada
# EDITE todos los valores REEMPLAZAR_* antes de importar.
# No es la clave Wi-Fi: es PrivateKey del archivo WireGuard entregado por Proton.

# Punto de acceso para el paquete legacy "wireless" mostrado por wlan1/wlan2.
# Ambas radios ya pertenecen a bridge1; no se vuelven a agregar al bridge.
/interface wireless security-profiles
add name=tik-casa-security mode=dynamic-keys authentication-types=wpa2-psk \
    unicast-ciphers=aes-ccm group-ciphers=aes-ccm \
    wpa2-pre-shared-key="REEMPLAZAR_CLAVE_WIFI" supplicant-identity=MikroTik

/interface wireless
set [find default-name=wlan1] mode=ap-bridge ssid="TIK-CASA" \
    security-profile=tik-casa-security disabled=no
set [find default-name=wlan2] mode=ap-bridge ssid="TIK-CASA" \
    security-profile=tik-casa-security disabled=no

/interface wireguard
add name=proton-wg mtu=1420 private-key="REEMPLAZAR_CLAVE_PRIVADA" comment="Proton WireGuard"

/ip address
add address=192.168.1.2/24 interface=ether1 comment="WAN hacia gateway ADSL"
add address=192.168.88.1/24 interface=bridge1 comment="Gateway LAN TIK-CASA"
add address=10.2.0.2/32 interface=proton-wg comment="Proton IPv4"

/ip pool
add name=tik-casa-pool ranges=192.168.88.10-192.168.88.254

/ip dhcp-server
add name=tik-casa-dhcp interface=bridge1 address-pool=tik-casa-pool lease-time=1h authoritative=yes disabled=no

/ip dhcp-server network
add address=192.168.88.0/24 gateway=192.168.88.1 dns-server=192.168.88.1 comment="LAN TIK-CASA"

/interface wireguard peers
add interface=proton-wg public-key="REEMPLAZAR_PUBLIC_KEY_PROTON" endpoint-address=REEMPLAZAR_ENDPOINT_PROTON endpoint-port=51820 allowed-address=0.0.0.0/0 persistent-keepalive=25s comment="Proton WireGuard peer"

/routing table
add fib name=to-proton

# Evitan que el endpoint VPN y el portal cautivo intenten cruzar el propio tunel.
/ip route
add dst-address=REEMPLAZAR_ENDPOINT_PROTON/32 gateway=192.168.1.1 routing-table=main comment="ADSL directo: endpoint Proton"
add dst-address=10.180.0.30/32 gateway=192.168.1.1 routing-table=main comment="ADSL directo: portal ETECSA"
add dst-address=10.2.0.1/32 gateway=proton-wg routing-table=main comment="DNS Proton para el router"
add dst-address=0.0.0.0/0 gateway=proton-wg routing-table=to-proton comment="Default LAN por Proton"

# La excepcion del portal debe aparecer antes de la regla LAN. La segunda regla es kill switch.
/routing rule
add dst-address=10.180.0.30/32 action=lookup-only-in-table table=main comment="Portal ETECSA por ADSL"
add interface=bridge1 action=lookup-only-in-table table=to-proton comment="LAN solo por Proton"

/ip firewall nat
add chain=srcnat dst-address=10.180.0.30 out-interface=ether1 action=masquerade comment="Portal ETECSA por ADSL"
add chain=srcnat out-interface=proton-wg action=masquerade comment="Proton: NAT LAN"

# Reduce problemas de PMTU en el tunel.
/ip firewall mangle
add chain=forward out-interface=proton-wg protocol=tcp tcp-flags=syn action=change-mss new-mss=clamp-to-pmtu comment="Proton: clamp MSS"

# DNS privado de Proton; el DHCP predeterminado normalmente anuncia la IP del router.
/ip dns
set servers=10.2.0.1 allow-remote-requests=yes

# Permite resolver el portal antes de que Proton DNS sea alcanzable.
/ip dns static
add name=secure.etecsa.net address=10.180.0.30 type=A comment="Portal ETECSA antes de VPN"
