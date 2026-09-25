# hAP ac3 canonical policy configuration
# Target: RBD53iG-5HacD2HnD, RouterOS 7.20.8 only
# IMPORTANT: review hap-ac3-routeros-7.20.8-deployment.md before importing.
# This file deliberately aborts until every value in USER INPUTS is filled.

# ============================================================================
# PHASE 0 - USER INPUTS AND SAFETY GUARDS
# ============================================================================
:local starlinkPort ""
:local adslPort ""
:local omnitikPort ""
:local trustedManagementCidr ""

:if ([:len $starlinkPort] = 0) do={ :error "SET starlinkPort (physical port connected to Starlink)" }
:if ([:len $adslPort] = 0) do={ :error "SET adslPort (physical port connected to ADSL LAN)" }
:if ([:len $omnitikPort] = 0) do={ :error "SET omnitikPort (physical port connected to OmniTik)" }
:if ([:len $trustedManagementCidr] = 0) do={ :error "SET trustedManagementCidr before installing the input firewall" }
:if (($starlinkPort = $adslPort) || ($starlinkPort = $omnitikPort) || ($adslPort = $omnitikPort)) do={ :error "Interface roles must use three different physical ports" }
:if ([:len [/interface find where name=$starlinkPort]] != 1) do={ :error "starlinkPort does not identify exactly one interface" }
:if ([:len [/interface find where name=$adslPort]] != 1) do={ :error "adslPort does not identify exactly one interface" }
:if ([:len [/interface find where name=$omnitikPort]] != 1) do={ :error "omnitikPort does not identify exactly one interface" }

# Refuse a second application rather than silently duplicate policy rules.
:if ([:len [/ip firewall filter find where comment="CANONICAL: input established"]] > 0) do={ :error "Canonical configuration already appears to be installed" }

# Backups are intentionally taken before the first configuration change.
/system backup save name="pre-canonical-7.20.8" dont-encrypt=no
/export hide-sensitive file="pre-canonical-7.20.8"

# ============================================================================
# PHASE 1 - INTERFACE PREPARATION
# ============================================================================
# The supplied export has no bridge membership to migrate. Wi-Fi is preserved
# exactly as exported and is not silently joined to either managed LAN.
/interface set [find where name=$starlinkPort] name=WAN_STARLINK comment="Starlink router LAN; isolated VRF"
/interface set [find where name=$adslPort] name=LAN_ADSL comment="Existing ADSL LAN; main table"
/interface set [find where name=$omnitikPort] name=LAN_OMNITIK comment="Managed 192.168.88.0/24 toward OmniTik AP/bridge"

# Interface lists make the policy auditable.
/interface list add name=CANONICAL_MANAGED comment="Canonical managed-side interfaces"
/interface list member add list=CANONICAL_MANAGED interface=LAN_OMNITIK

# ============================================================================
# PHASE 2 - STARLINK VRF (must precede main/interfaces=all)
# ============================================================================
/ip vrf add name=vrf-starlink interfaces=WAN_STARLINK place-before=[find where name=main] comment="Overlapping Starlink 192.168.1.0/24"

# ============================================================================
# PHASE 3 - ADDRESSING AND WAN DHCP
# ============================================================================
/ip address add address=192.168.1.254/24 interface=LAN_ADSL comment="Canonical ADSL-side policy gateway"
/ip address add address=192.168.88.1/24 interface=LAN_OMNITIK comment="Canonical managed-LAN gateway"

# Because WAN_STARLINK belongs to the VRF, its DHCP address, connected route,
# and dynamic default route are installed in vrf-starlink.
/ip dhcp-client add interface=WAN_STARLINK add-default-route=yes use-peer-dns=no use-peer-ntp=no disabled=no comment="Canonical Starlink DHCP in VRF"

# Main has an explicit ADSL default. It is used only where policy does not mark
# the packet for vrf-starlink (notably FORCE_ADSL destinations).
/ip route add dst-address=0.0.0.0/0 gateway=192.168.1.1%LAN_ADSL routing-table=main distance=1 comment="Canonical ADSL default"

# ============================================================================
# PHASE 4 - MANAGED DHCP/ARP
# ============================================================================
/ip dhcp-server add name=DHCP_OMNITIK interface=LAN_OMNITIK address-pool=static-only lease-time=1d add-arp=yes authoritative=yes disabled=no comment="Canonical static-only managed DHCP"
/ip dhcp-server network add address=192.168.88.0/24 gateway=192.168.88.1 dns-server=192.168.88.1 comment="Canonical managed DHCP options"
/interface ethernet set [find where name=LAN_OMNITIK] arp=reply-only

# REQUIRED DEVICE ENTRIES - duplicate and uncomment one pair per managed device.
# The lease address and firewall address-list MUST agree.
# /ip dhcp-server lease add server=DHCP_OMNITIK mac-address=AA:BB:CC:DD:EE:01 address=192.168.88.10 comment="DEVICE - Odoo only"
# /ip firewall address-list add list=OMNI_ODOO_ONLY address=192.168.88.10 comment="DEVICE - Odoo only"
# /ip dhcp-server lease add server=DHCP_OMNITIK mac-address=AA:BB:CC:DD:EE:02 address=192.168.88.20 comment="DEVICE - Odoo + Starlink"
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
/ip route add dst-address=192.168.88.0/24 gateway=LAN_OMNITIK@main routing-table=vrf-starlink comment="Canonical VRF return to managed LAN"

# ============================================================================
# PHASE 5 - DNS AND DOMAIN-TO-ADDRESS-LIST POLICY
# ============================================================================
# RouterOS 7.20.8 DNS listens in main. Managed and authorized clients use this
# cache; upstream DNS follows the main/ADSL route. Dynamic list members expire
# according to the received DNS TTL.
/ip dns set allow-remote-requests=yes servers=1.1.1.1,9.9.9.9 cache-size=4096KiB address-list-extra-time=0s

# REQUIRED FORCE_ADSL ENTRIES - use name plus match-subdomain=yes to cover the
# apex and subdomains. Duplicate for every approved domain.
# /ip dns static add name=example.com type=FWD forward-to=1.1.1.1 match-subdomain=yes address-list=FORCE_ADSL comment="FORCE_ADSL domain"

# Redirect classic DNS from policy clients to the hAP cache. DoH/DoT is not
# intercepted; see the deployment document for the explicit limitation.
/ip firewall nat add chain=dstnat src-address-list=ADSL_STARLINK protocol=udp dst-port=53 action=redirect to-ports=53 comment="Canonical: control ADSL client UDP DNS"
/ip firewall nat add chain=dstnat src-address-list=ADSL_STARLINK protocol=tcp dst-port=53 action=redirect to-ports=53 comment="Canonical: control ADSL client TCP DNS"
/ip firewall nat add chain=dstnat in-interface=LAN_OMNITIK protocol=udp dst-port=53 action=redirect to-ports=53 comment="Canonical: control managed UDP DNS"
/ip firewall nat add chain=dstnat in-interface=LAN_OMNITIK protocol=tcp dst-port=53 action=redirect to-ports=53 comment="Canonical: control managed TCP DNS"

# ============================================================================
# PHASE 6 - POLICY ROUTING
# ============================================================================
# Never mark Odoo or FORCE_ADSL traffic for Starlink. Mangle has precedence over
# ordinary route rules, so these accept rules deliberately precede mark-routing.
/ip firewall mangle add chain=prerouting dst-address=192.168.1.250 action=accept comment="Canonical: keep Odoo in main"
/ip firewall mangle add chain=prerouting dst-address-list=FORCE_ADSL action=accept comment="Canonical: keep forced domains on ADSL/main"
/ip firewall mangle add chain=prerouting in-interface=LAN_ADSL src-address-list=ADSL_STARLINK dst-address-type=!local action=mark-routing new-routing-mark=vrf-starlink passthrough=no comment="Canonical: authorized ADSL to Starlink VRF"
/ip firewall mangle add chain=prerouting in-interface=LAN_OMNITIK src-address-list=OMNI_ODOO_STARLINK dst-address-type=!local action=mark-routing new-routing-mark=vrf-starlink passthrough=no comment="Canonical: managed Internet to Starlink VRF"

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
/ip firewall address-list add list=TRUSTED_MANAGEMENT address=$trustedManagementCidr comment="Canonical administrator source"
/ip firewall filter add chain=input connection-state=established,related,untracked action=accept comment="CANONICAL: input established"
/ip firewall filter add chain=input connection-state=invalid action=drop comment="CANONICAL: input invalid"
/ip firewall filter add chain=input protocol=icmp src-address-list=TRUSTED_MANAGEMENT action=accept comment="CANONICAL: trusted ICMP"
/ip firewall filter add chain=input in-interface=LAN_OMNITIK protocol=udp src-port=68 dst-port=67 action=accept comment="CANONICAL: managed DHCP"
/ip firewall filter add chain=input in-interface=LAN_OMNITIK protocol=udp dst-port=53 action=accept comment="CANONICAL: managed DNS UDP"
/ip firewall filter add chain=input in-interface=LAN_OMNITIK protocol=tcp dst-port=53 action=accept comment="CANONICAL: managed DNS TCP"
/ip firewall filter add chain=input src-address-list=ADSL_STARLINK protocol=udp dst-port=53 action=accept comment="CANONICAL: authorized ADSL DNS UDP"
/ip firewall filter add chain=input src-address-list=ADSL_STARLINK protocol=tcp dst-port=53 action=accept comment="CANONICAL: authorized ADSL DNS TCP"
/ip firewall filter add chain=input src-address-list=TRUSTED_MANAGEMENT protocol=tcp dst-port=22,8291 action=accept comment="CANONICAL: trusted SSH and WinBox"
/ip firewall filter add chain=input action=drop log=yes log-prefix="DROP_INPUT " comment="CANONICAL: input default deny"

# Limit service daemons as defense in depth. WebFig, API, FTP and Telnet remain
# disabled; SSH and WinBox are still protected by the input rules above.
/ip service set telnet disabled=yes
/ip service set ftp disabled=yes
/ip service set www disabled=yes
/ip service set www-ssl disabled=yes
/ip service set api disabled=yes
/ip service set api-ssl disabled=yes
/ip service set ssh disabled=no address=$trustedManagementCidr
/ip service set winbox disabled=no address=$trustedManagementCidr
/ip socks set enabled=no
/ip upnp set enabled=no
/ip proxy set enabled=no

# ============================================================================
# PHASE 9 - FIREWALL FORWARD
# ============================================================================
/ip firewall filter add chain=forward connection-state=established,related,untracked action=accept comment="CANONICAL: forward established"
/ip firewall filter add chain=forward connection-state=invalid action=drop comment="CANONICAL: forward invalid"

# Odoo ports are intentionally placeholders. Add exact allow rules BEFORE the
# Odoo deny rule after confirming whether Odoo uses 443, 8069, or other ports.
# /ip firewall filter add chain=forward src-address-list=OMNI_ODOO_ONLY dst-address=192.168.1.250 protocol=tcp dst-port=443 action=accept comment="Odoo-only DEVICE: approved Odoo TCP"
# /ip firewall filter add chain=forward src-address-list=OMNI_ODOO_STARLINK dst-address=192.168.1.250 protocol=tcp dst-port=443 action=accept comment="Odoo+Starlink DEVICE: approved Odoo TCP"
/ip firewall filter add chain=forward in-interface=LAN_OMNITIK dst-address=192.168.1.250 action=reject reject-with=icmp-admin-prohibited comment="CANONICAL: reject unapproved Odoo ports"

# FORCE_ADSL takes priority and is allowed only for Internet-capable groups.
/ip firewall filter add chain=forward src-address-list=OMNI_ODOO_STARLINK dst-address-list=FORCE_ADSL out-interface=LAN_ADSL action=accept comment="CANONICAL: managed forced domain"

# General Starlink permits. ADSL clients require the per-device IP+MAC rules
# created from the phase 4 template; group membership alone is insufficient.
/ip firewall filter add chain=forward src-address-list=OMNI_ODOO_STARLINK out-interface=vrf-starlink action=accept comment="CANONICAL: managed authorized Starlink"
/ip firewall filter add chain=forward in-interface=LAN_ADSL action=reject reject-with=icmp-admin-prohibited log=yes log-prefix="DENY_ADSL_GW " comment="CANONICAL: reject unauthorized ADSL gateway use"
/ip firewall filter add chain=forward in-interface=LAN_OMNITIK action=reject reject-with=icmp-admin-prohibited log=yes log-prefix="DENY_MANAGED " comment="CANONICAL: managed default deny"
/ip firewall filter add chain=forward action=drop log=yes log-prefix="DROP_FORWARD " comment="CANONICAL: forward default deny"

# FastTrack is intentionally absent: it can bypass mangle/policy-routing work.
# Block IPv6 forwarding from policy segments until an explicit IPv6 design is
# approved, preventing an ungoverned IPv6 path without disabling router IPv6.
/ipv6 firewall filter add chain=forward in-interface=LAN_ADSL action=drop comment="CANONICAL: no ungoverned ADSL IPv6 forwarding"
/ipv6 firewall filter add chain=forward in-interface=LAN_OMNITIK action=drop comment="CANONICAL: no ungoverned managed IPv6 forwarding"

:put "Canonical base installed. Complete external changes and run every validation in the deployment document."
