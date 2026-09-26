# hAP ac3 canonical policy configuration
# Target: RBD53iG-5HacD2HnD, RouterOS 7.20.8 only
# IMPORTANT: review hap-ac3-routeros-7.20.8-deployment.md before importing.
# Physical map: ether1=Starlink, ether2=ADSL, ether3=OmniTik.
# This file aborts until the mandatory USER INPUTS are valid.
# BEFORE IMPORT: fill the eight variables below and only those ADSL_STARLINK
# clients required on day one.
# DO NOT pre-fill future OmniTik/Wi-Fi clients: discover and authorize them
# after import through POOL_ENROLLMENT as documented in the deployment guide.

:do {

# ============================================================================
# PHASE 0 - USER INPUTS AND SAFETY GUARDS
# ============================================================================
# Administrator identity: BOTH values must match. For one host use /32.
:local trustedManagementIpCidr ""
:local trustedManagementMac ""
:local wifiSSID ""
:local wifiPassphrase ""
# For a device physically installed in the United States, use "united states".
:local wifiCountry ""
# Comma-separated RouterOS port lists, without spaces; ranges are accepted.
# Leave one protocol empty only when Odoo does not use that protocol.
:local odooTcpPorts ""
:local odooUdpPorts ""
# Comma-separated domain names only: no spaces, scheme, port or URL path.
# match-subdomain=yes makes every entry cover its apex and subdomains.
:local forceAdslDomains ""

# This configuration has been reviewed only for this exact hardware/OS pair.
# Abort before backups or configuration changes on any other target.
:local installedVersion [/system resource get version]
:local installedBoard [/system resource get board-name]
:if (($installedVersion != "7.20.8") && ($installedVersion != "7.20.8 (long-term)")) do={ :error ("Unsupported RouterOS version: " . $installedVersion . "; expected 7.20.8") }
:if ($installedBoard != "hAP ac^3") do={ :error ("Unsupported board: " . $installedBoard . "; expected hAP ac^3") }

:if ([:len $trustedManagementIpCidr] = 0) do={ :error "SET trustedManagementIpCidr (use /32 for one host)" }
:if ([:len $trustedManagementMac] = 0) do={ :error "SET trustedManagementMac" }
:if ([:len $wifiSSID] = 0) do={ :error "SET wifiSSID" }
:if (([:len $wifiPassphrase] < 8) || ([:len $wifiPassphrase] > 63)) do={ :error "wifiPassphrase must contain 8 to 63 characters" }
:if ([:len $wifiCountry] = 0) do={ :error "SET wifiCountry to the RouterOS country value for the installation" }
:if (([:len $odooTcpPorts] = 0) && ([:len $odooUdpPorts] = 0)) do={ :error "SET at least one of odooTcpPorts or odooUdpPorts" }
:if (([:typeof [:find $odooTcpPorts " "]] != "nil") || ([:typeof [:find $odooUdpPorts " "]] != "nil")) do={ :error "Odoo port lists must not contain spaces" }
:if ([:len $forceAdslDomains] = 0) do={ :error "SET forceAdslDomains" }
:if (([:typeof [:find $forceAdslDomains " "]] != "nil") || ([:typeof [:find $forceAdslDomains "://"]] != "nil") || ([:typeof [:find $forceAdslDomains "/"]] != "nil")) do={ :error "forceAdslDomains must contain comma-separated domain names only" }
:if (([:len [/interface find where name=ether1]] != 1) || ([:len [/interface find where name=ether2]] != 1) || ([:len [/interface find where name=ether3]] != 1)) do={ :error "Expected default interfaces ether1, ether2 and ether3" }
:if (([:len [/interface find where default-name=wlan1]] != 1) || ([:len [/interface find where default-name=wlan2]] != 1)) do={ :error "Expected legacy wireless interfaces wlan1 and wlan2" }

# Refuse a second application rather than silently duplicate policy rules.
:if ([:len [/ip firewall filter find where comment="CANONICAL: input established"]] > 0) do={ :error "Canonical configuration already appears to be installed" }

# Backups are intentionally taken before the first configuration change.
/system backup save name="pre-canonical-7.20.8" dont-encrypt=no
/export hide-sensitive file="pre-canonical-7.20.8"

# ============================================================================
# PHASE 1 - INTERFACE PREPARATION
# ============================================================================
# Fixed cabling requested for this deployment.
/interface set [find where name=ether1] name=WAN_STARLINK comment="CONNECT STARLINK HERE; isolated VRF"
/interface set [find where name=ether2] name=LAN_ADSL comment="CONNECT EXISTING ADSL LAN HERE; main table"
/interface set [find where name=ether3] name=LAN_OMNITIK comment="CONNECT OMNITIK HERE; AP/bridge uplink"

# ether3, wlan1 and wlan2 are one managed 192.168.88.0/24 broadcast domain.
/interface bridge add name=BR_MANAGED arp=reply-only protocol-mode=rstp comment="OmniTik plus hAP Wi-Fi managed LAN"
/interface bridge port add bridge=BR_MANAGED interface=LAN_OMNITIK comment="OmniTik uplink"
/interface bridge port add bridge=BR_MANAGED interface=wlan1 comment="hAP 2.4 GHz managed WLAN"
/interface bridge port add bridge=BR_MANAGED interface=wlan2 comment="hAP 5 GHz managed WLAN"
/interface wireless security-profiles add name=CANONICAL_WIFI authentication-types=wpa2-psk mode=dynamic-keys unicast-ciphers=aes-ccm group-ciphers=aes-ccm wpa2-pre-shared-key=$wifiPassphrase supplicant-identity=MikroTik
/interface wireless set [find where default-name=wlan1] mode=ap-bridge ssid=$wifiSSID country=$wifiCountry installation=indoor security-profile=CANONICAL_WIFI disabled=no
/interface wireless set [find where default-name=wlan2] mode=ap-bridge ssid=$wifiSSID country=$wifiCountry installation=indoor security-profile=CANONICAL_WIFI disabled=no

# Interface lists make the policy auditable.
/interface list add name=CANONICAL_MANAGED comment="Canonical managed-side interfaces"
/interface list member add list=CANONICAL_MANAGED interface=BR_MANAGED

# ============================================================================
# PHASE 2 - STARLINK VRF (must precede main/interfaces=all)
# ============================================================================
/ip vrf add name=vrf-starlink interfaces=WAN_STARLINK place-before=[find where name=main] comment="Overlapping Starlink 192.168.1.0/24"

# RouterOS creates the routing table mapped to a VRF dynamically. On 7.20.8
# that table can become visible shortly after /ip vrf add returns. Wait up to
# five seconds so later static routes and routing marks cannot race its creation.
:local vrfTableReady false
:for vrfWaitAttempt from=1 to=50 do={
    :if ([:len [/routing table find where name="vrf-starlink"]] = 1) do={
        :set vrfTableReady true
        :break
    }
    :delay 100ms
}
:if ($vrfTableReady = false) do={ :error "vrf-starlink routing table was not created within 5 seconds" }

# ============================================================================
# PHASE 3 - ADDRESSING AND WAN DHCP
# ============================================================================
/ip address add address=192.168.1.254/24 interface=LAN_ADSL comment="Canonical ADSL-side policy gateway"
/ip address add address=192.168.88.1/24 interface=BR_MANAGED comment="Canonical OmniTik/Wi-Fi gateway"

# Because WAN_STARLINK belongs to the VRF, its DHCP address, connected route,
# and dynamic default route are installed in vrf-starlink.
/ip dhcp-client add interface=WAN_STARLINK add-default-route=yes use-peer-dns=no use-peer-ntp=no disabled=no comment="Canonical Starlink DHCP in VRF"

# Main has an explicit ADSL default. It is used only where policy does not mark
# the packet for vrf-starlink (notably FORCE_ADSL destinations).
/ip route add dst-address=0.0.0.0/0 gateway=192.168.1.1%LAN_ADSL routing-table=main distance=1 comment="Canonical ADSL default"

# ============================================================================
# PHASE 4 - MANAGED DHCP/ARP
# ============================================================================
/ip pool add name=POOL_ENROLLMENT ranges=192.168.88.200-192.168.88.239 comment="Quarantine/onboarding only; no forwarding group"
/ip dhcp-server add name=DHCP_MANAGED interface=BR_MANAGED address-pool=POOL_ENROLLMENT lease-time=1h add-arp=yes authoritative=yes disabled=no comment="Managed DHCP; unknown clients remain quarantined"
/ip dhcp-server network add address=192.168.88.0/24 gateway=192.168.88.1 dns-server=192.168.88.1 comment="Canonical managed DHCP options"

# REQUIRED DEVICE ENTRIES - duplicate and uncomment one pair per managed device.
# The lease address and firewall address-list MUST agree.
# Unknown clients may receive 192.168.88.200-239 only so the administrator can
# discover their MAC. They have no Odoo/Internet permission until converted to
# a static lease in 192.168.88.10-199 and added to exactly one policy list.
# /ip dhcp-server lease add server=DHCP_MANAGED mac-address=AA:BB:CC:DD:EE:01 address=192.168.88.10 comment="DEVICE - Odoo only"
# /ip firewall address-list add list=OMNI_ODOO_ONLY address=192.168.88.10 comment="DEVICE - Odoo only"
# /ip dhcp-server lease add server=DHCP_MANAGED mac-address=AA:BB:CC:DD:EE:02 address=192.168.88.20 comment="DEVICE - Odoo + Starlink (use for wlan1/wlan2 clients)"
# /ip firewall address-list add list=OMNI_ODOO_STARLINK address=192.168.88.20 comment="DEVICE - Odoo + Starlink"

# REQUIRED ADSL_STARLINK ENTRIES - duplicate all four lines per device.
# The /32 is essential: it overrides Starlink's connected 192.168.1.0/24 on
# return traffic. Both filter lines bind the allowed IP to its expected MAC;
# an address-list membership alone never grants forwarding.
# /ip firewall address-list add list=ADSL_STARLINK address=192.168.1.30 comment="DEVICE - authorized ADSL client"
# /ip route add dst-address=192.168.1.30/32 gateway=LAN_ADSL@main routing-table=vrf-starlink comment="DEVICE - VRF return to authorized ADSL client"
# /ip firewall filter add chain=forward in-interface=LAN_ADSL src-address=192.168.1.30 src-mac-address=AA:BB:CC:DD:EE:03 dst-address-list=FORCE_ADSL out-interface=LAN_ADSL connection-state=new action=accept comment="DEVICE - IP+MAC authorize FORCE_ADSL"
# /ip firewall filter add chain=forward in-interface=LAN_ADSL src-address=192.168.1.30 src-mac-address=AA:BB:CC:DD:EE:03 out-interface=vrf-starlink connection-state=new action=accept comment="DEVICE - IP+MAC authorize Starlink"

# The managed subnet also needs an explicit VRF-to-main return leak.
/ip route add dst-address=192.168.88.0/24 gateway=BR_MANAGED@main routing-table=vrf-starlink comment="Canonical VRF return to OmniTik/Wi-Fi LAN"

# ============================================================================
# PHASE 5 - DNS AND DOMAIN-TO-ADDRESS-LIST POLICY
# ============================================================================
# RouterOS 7.20.8 DNS listens in main. Managed and authorized clients use this
# cache; upstream DNS follows the main/ADSL route. Dynamic list members expire
# according to the received DNS TTL.
/ip dns set allow-remote-requests=yes servers=1.1.1.1,9.9.9.9 cache-size=4096KiB address-list-extra-time=0s

# Generate one DNS forward entry per Phase 0 domain. match-subdomain=yes covers
# the apex and its subdomains; learned addresses expire with the received TTL.
:foreach domain in=[:toarray $forceAdslDomains] do={
    /ip dns static add name=$domain type=FWD forward-to=1.1.1.1 match-subdomain=yes address-list=FORCE_ADSL comment=("FORCE_ADSL: " . $domain)
}

# Redirect classic DNS from policy clients to the hAP cache. DoH/DoT is not
# intercepted; see the deployment document for the explicit limitation.
/ip firewall nat add chain=dstnat src-address-list=ADSL_STARLINK protocol=udp dst-port=53 action=redirect to-ports=53 comment="Canonical: control ADSL client UDP DNS"
/ip firewall nat add chain=dstnat src-address-list=ADSL_STARLINK protocol=tcp dst-port=53 action=redirect to-ports=53 comment="Canonical: control ADSL client TCP DNS"
/ip firewall nat add chain=dstnat in-interface=BR_MANAGED protocol=udp dst-port=53 action=redirect to-ports=53 comment="Canonical: control managed UDP DNS"
/ip firewall nat add chain=dstnat in-interface=BR_MANAGED protocol=tcp dst-port=53 action=redirect to-ports=53 comment="Canonical: control managed TCP DNS"

# ============================================================================
# PHASE 6 - POLICY ROUTING
# ============================================================================
# Never mark Odoo or FORCE_ADSL traffic for Starlink. Mangle has precedence over
# ordinary route rules, so these accept rules deliberately precede mark-routing.
/ip firewall mangle add chain=prerouting dst-address=192.168.1.250 action=accept comment="Canonical: keep Odoo in main"
/ip firewall mangle add chain=prerouting dst-address-list=FORCE_ADSL action=accept comment="Canonical: keep forced domains on ADSL/main"
/ip firewall mangle add chain=prerouting in-interface=LAN_ADSL src-address-list=ADSL_STARLINK dst-address-type=!local action=mark-routing new-routing-mark=vrf-starlink passthrough=no comment="Canonical: authorized ADSL to Starlink VRF"
/ip firewall mangle add chain=prerouting in-interface=BR_MANAGED src-address-list=OMNI_ODOO_STARLINK dst-address-type=!local action=mark-routing new-routing-mark=vrf-starlink passthrough=no comment="Canonical: OmniTik/Wi-Fi Internet to Starlink VRF"

# ============================================================================
# PHASE 7 - NARROW NAT
# ============================================================================
# No NAT rule matches Odoo. Starlink is dynamic, so masquerade is appropriate.
/ip firewall nat add chain=srcnat routing-mark=vrf-starlink out-interface=vrf-starlink action=masquerade comment="Canonical: Starlink Internet only"
# Managed clients need NAT for forced ADSL domains because the ADSL router has
# no general return route for 192.168.88.0/24. ADSL-side clients do not.
/ip firewall nat add chain=srcnat src-address=192.168.88.0/24 dst-address-list=FORCE_ADSL out-interface=LAN_ADSL action=masquerade comment="Canonical: managed FORCE_ADSL only"

# ============================================================================
# PHASE 8 - FIREWALL INPUT (router services)
# ============================================================================
/ip firewall filter add chain=input connection-state=established,related,untracked action=accept comment="CANONICAL: input established"
/ip firewall filter add chain=input connection-state=invalid action=drop comment="CANONICAL: input invalid"
/ip firewall filter add chain=input src-address=$trustedManagementIpCidr src-mac-address=$trustedManagementMac protocol=icmp action=accept comment="CANONICAL: administrator IP+MAC ICMP"
/ip firewall filter add chain=input in-interface=BR_MANAGED protocol=udp src-port=68 dst-port=67 action=accept comment="CANONICAL: managed DHCP"
/ip firewall filter add chain=input in-interface=BR_MANAGED protocol=udp dst-port=53 action=accept comment="CANONICAL: managed DNS UDP"
/ip firewall filter add chain=input in-interface=BR_MANAGED protocol=tcp dst-port=53 action=accept comment="CANONICAL: managed DNS TCP"
/ip firewall filter add chain=input src-address-list=ADSL_STARLINK protocol=udp dst-port=53 action=accept comment="CANONICAL: authorized ADSL DNS UDP"
/ip firewall filter add chain=input src-address-list=ADSL_STARLINK protocol=tcp dst-port=53 action=accept comment="CANONICAL: authorized ADSL DNS TCP"
/ip firewall filter add chain=input src-address=$trustedManagementIpCidr src-mac-address=$trustedManagementMac protocol=tcp dst-port=22,8291 action=accept comment="CANONICAL: administrator IP+MAC SSH and WinBox"
/ip firewall filter add chain=input action=drop log=yes log-prefix="DROP_INPUT " comment="CANONICAL: input default deny"

# Limit service daemons as defense in depth. WebFig, API, FTP and Telnet remain
# disabled; SSH and WinBox are still protected by the input rules above.
/ip service set telnet disabled=yes
/ip service set ftp disabled=yes
/ip service set www disabled=yes
/ip service set www-ssl disabled=yes
/ip service set api disabled=yes
/ip service set api-ssl disabled=yes
/ip service set ssh disabled=no address=$trustedManagementIpCidr
/ip service set winbox disabled=no address=$trustedManagementIpCidr
/ip socks set enabled=no
/ip upnp set enabled=no
/ip proxy set enabled=no

# ============================================================================
# PHASE 9 - FIREWALL FORWARD
# ============================================================================
/ip firewall filter add chain=forward connection-state=established,related,untracked action=accept comment="CANONICAL: forward established"
/ip firewall filter add chain=forward connection-state=invalid action=drop comment="CANONICAL: forward invalid"

# The two Phase 0 port variables generate these rules before the Odoo deny.
# Both managed groups receive exactly the same approved Odoo application ports.
:if ([:len $odooTcpPorts] > 0) do={
    /ip firewall filter add chain=forward src-address-list=OMNI_ODOO_ONLY dst-address=192.168.1.250 protocol=tcp dst-port=$odooTcpPorts action=accept comment="CANONICAL: Odoo-only approved TCP"
    /ip firewall filter add chain=forward src-address-list=OMNI_ODOO_STARLINK dst-address=192.168.1.250 protocol=tcp dst-port=$odooTcpPorts action=accept comment="CANONICAL: Odoo+Starlink approved TCP"
}
:if ([:len $odooUdpPorts] > 0) do={
    /ip firewall filter add chain=forward src-address-list=OMNI_ODOO_ONLY dst-address=192.168.1.250 protocol=udp dst-port=$odooUdpPorts action=accept comment="CANONICAL: Odoo-only approved UDP"
    /ip firewall filter add chain=forward src-address-list=OMNI_ODOO_STARLINK dst-address=192.168.1.250 protocol=udp dst-port=$odooUdpPorts action=accept comment="CANONICAL: Odoo+Starlink approved UDP"
}
/ip firewall filter add chain=forward in-interface=BR_MANAGED dst-address=192.168.1.250 action=reject reject-with=icmp-admin-prohibited comment="CANONICAL: reject unapproved Odoo ports"

# FORCE_ADSL takes priority and is allowed only for Internet-capable groups.
/ip firewall filter add chain=forward src-address-list=OMNI_ODOO_STARLINK dst-address-list=FORCE_ADSL out-interface=LAN_ADSL action=accept comment="CANONICAL: managed forced domain"

# General Starlink permits. ADSL clients require the per-device IP+MAC rules
# created from the phase 4 template; group membership alone is insufficient.
/ip firewall filter add chain=forward src-address-list=OMNI_ODOO_STARLINK out-interface=vrf-starlink action=accept comment="CANONICAL: managed authorized Starlink"
/ip firewall filter add chain=forward in-interface=LAN_ADSL action=reject reject-with=icmp-admin-prohibited log=yes log-prefix="DENY_ADSL_GW " comment="CANONICAL: reject unauthorized ADSL gateway use"
/ip firewall filter add chain=forward in-interface=BR_MANAGED action=reject reject-with=icmp-admin-prohibited log=yes log-prefix="DENY_MANAGED " comment="CANONICAL: managed default deny"
/ip firewall filter add chain=forward action=drop log=yes log-prefix="DROP_FORWARD " comment="CANONICAL: forward default deny"

# FastTrack is intentionally absent: it can bypass mangle/policy-routing work.
# Block IPv6 forwarding from policy segments until an explicit IPv6 design is
# approved, preventing an ungoverned IPv6 path without disabling router IPv6.
/ipv6 firewall filter add chain=forward in-interface=LAN_ADSL action=drop comment="CANONICAL: no ungoverned ADSL IPv6 forwarding"
/ipv6 firewall filter add chain=forward in-interface=BR_MANAGED action=drop comment="CANONICAL: no ungoverned managed IPv6 forwarding"

:put "Canonical base installed. Complete external changes and run every validation in the deployment document."

}
