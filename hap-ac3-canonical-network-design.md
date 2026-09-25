# Canonical Network Design — MikroTik hAP ac3

**Document purpose:** canonical specification for Codex to generate the final RouterOS 7 configuration for the MikroTik hAP ac3.

**Status:** Approved architecture baseline  
**Target device:** MikroTik hAP ac3  
**Target OS:** RouterOS 7.x  
**Configuration style:** explicit, auditable, deny-by-default, no hidden assumptions

---

## 1. Objective

The hAP ac3 must become the policy enforcement point that controls which devices may:

1. Access the Odoo server.
2. Access Internet through Starlink.
3. Access only the Odoo server and no Internet.
4. Use Starlink for general Internet but force selected domains to use ADSL.
5. Be authorized by administrator-controlled device identity, not merely by knowing the hAP gateway IP.

The existing ADSL network must continue operating with minimal disruption.

---

## 2. Existing network

### 2.1 ADSL LAN

- Network: `192.168.1.0/24`
- ADSL router/gateway: `192.168.1.1`
- DHCP: currently provided by the ADSL network/router
- Odoo server: `192.168.1.250`
- Existing workstations: `192.168.1.x`
- Normal ADSL workstations use:
  - Gateway: `192.168.1.1`

### 2.2 Starlink LAN

- Starlink router must remain in normal router mode.
- Starlink LAN network: `192.168.1.0/24`
- Starlink router/gateway: `192.168.1.1`
- Starlink DHCP: enabled
- The Starlink LAN overlaps exactly with the ADSL LAN.

This overlap is intentional and **must not be solved by renumbering either network**.

### 2.3 OmniTik network

- Current network: `192.168.88.0/24`
- Current OmniTik gateway: `192.168.88.1`
- Desired final role:
  - OmniTik becomes AP/bridge.
  - hAP ac3 becomes router, DHCP server, firewall and policy point for `192.168.88.0/24`.
- Desired hAP LAN address for this segment:
  - `192.168.88.1/24`
- Recommended OmniTik management IP after migration:
  - `192.168.88.2/24`

### 2.4 Odoo server

- IP: `192.168.1.250`
- Server is under administrator control.
- A static route may be added to the server.
- Required route:
  - Destination: `192.168.88.0/24`
  - Next hop: `192.168.1.254`

No NAT should be used between `192.168.88.0/24` and the Odoo server unless technically unavoidable.

---

## 3. hAP ac3 logical role

The hAP ac3 will have three logical sides:

### 3.1 Starlink WAN

- Connected directly to the Starlink router LAN.
- Must be placed in a dedicated VRF named, for example:
  - `vrf-starlink`
- The Starlink-facing interface must use DHCP client.
- The DHCP client and default route must belong to the Starlink VRF.

### 3.2 ADSL LAN attachment

- Connected to the existing ADSL LAN.
- hAP address:
  - `192.168.1.254/24`
- This interface remains in the main routing table.
- It must not provide DHCP to the existing `192.168.1.0/24` ADSL LAN.
- Existing ADSL workstations remain unchanged unless explicitly authorized for Starlink.

### 3.3 OmniTik / managed LAN

- Network:
  - `192.168.88.0/24`
- hAP gateway:
  - `192.168.88.1`
- DHCP server:
  - provided by hAP
- Prefer static DHCP leases for managed devices.
- OmniTik operates as bridge/AP only.

---

## 4. Mandatory architecture decision: overlapping networks

Both ADSL and Starlink use:

`192.168.1.0/24`  
Gateway: `192.168.1.1`

Therefore:

- Do **not** bridge the ADSL and Starlink interfaces.
- Do **not** place both networks in the same routing table.
- Do **not** attempt to resolve the conflict by renumbering.
- Do **not** rely on ambiguous connected routes.

The Starlink side must be isolated in a dedicated VRF.

The main routing table must continue to represent the ADSL-side `192.168.1.0/24`.

---

## 5. Device policy model

The hAP configuration must be designed around administrator-controlled device groups.

At minimum, implement these logical groups:

### 5.1 `ADSL_STARLINK`

Devices physically located in the ADSL LAN that are explicitly authorized to use Starlink Internet.

Characteristics:

- Device IP remains in `192.168.1.0/24`.
- Device gateway is manually/reserved as:
  - `192.168.1.254`
- Device must retain direct local access to:
  - `192.168.1.250` Odoo
  - other same-subnet resources according to normal Layer 2 behavior
- General Internet traffic must use Starlink.
- Forced-ADSL domains must use ADSL instead.

### 5.2 `OMNI_ODOO_ONLY`

Devices in `192.168.88.0/24` that may access Odoo but must not have unrestricted Internet access.

Allowed:

- Odoo server at `192.168.1.250`
- Only explicitly required supporting services, if any are later defined.

Denied:

- General Starlink Internet.
- General ADSL Internet.
- Unnecessary access to other ADSL LAN hosts.

### 5.3 `OMNI_ODOO_STARLINK`

Devices in `192.168.88.0/24` that may:

- Access Odoo.
- Access general Internet through Starlink.
- Use ADSL only for domains explicitly included in the forced-ADSL domain policy.

### 5.4 Normal ADSL devices

Devices on `192.168.1.0/24` that are not explicitly authorized for hAP routing:

- Continue using gateway `192.168.1.1`.
- Continue using ADSL.
- Must not gain Starlink access merely by pointing their gateway to `192.168.1.254`.

---

## 6. Security model

### 6.1 Core rule

Knowing or configuring the hAP gateway IP must **not** be sufficient to obtain Starlink access.

A device that points to:

`192.168.1.254`

but is not authorized must be denied forwarding through the hAP.

### 6.2 Authorization controls

Use a combination of:

- Static DHCP reservations where applicable.
- RouterOS address lists.
- IP identity.
- MAC identity where useful and technically applicable.
- Explicit firewall forward rules.
- Default-deny behavior for policy-controlled traffic.

For the managed `192.168.88.0/24` segment:

- Prefer DHCP leases tied to MAC addresses.
- Prefer `static-only` DHCP if compatible with the operational workflow.
- Consider controlled ARP / `reply-only` if it does not create operational problems.
- Document any limitations of MAC-based trust.

### 6.3 Important physical-security limitation

The ADSL LAN uses a non-managed switch.

Therefore, IP+MAC filtering prevents casual bypass such as:

- discovering `192.168.1.254`;
- manually configuring it as gateway.

However, it does not provide enterprise-grade protection against an attacker with LAN access who deliberately clones both the IP and MAC of an authorized device.

Do not claim otherwise.

---

## 7. Routing policy priority

The routing decision order must be conceptually:

1. Established / related connection handling.
2. Local/router management traffic.
3. Odoo destination handling.
4. Forced-ADSL domain destinations.
5. Authorized Starlink clients.
6. Explicit supporting services.
7. Default deny for traffic that depends on hAP authorization.

The forced-ADSL policy must have higher priority than the general Starlink policy.

Example:

- A device normally uses Starlink.
- It accesses `example-bank.com`.
- `example-bank.com` is in the forced-ADSL domain set.
- That connection must leave through ADSL.

---

## 8. Forced-ADSL domain policy

The requirement is domain-based, not full-URL-path-based.

Supported requirement examples:

- `example.com`
- `www.example.com`
- `*.example.com`

Not required:

- path-specific routing such as:
  - `https://example.com/specific/path`

The configuration must route selected domains through ADSL regardless of whether the client normally uses Starlink.

### 8.1 Preferred implementation

Use RouterOS DNS-driven address lists or an equivalent RouterOS-native mechanism that:

- resolves configured domains;
- tracks their IP addresses;
- respects DNS TTL where possible;
- supports subdomains where required;
- feeds a firewall/routing address list such as:
  - `FORCE_ADSL`

Traffic with destination in `FORCE_ADSL` must be policy-routed through the ADSL gateway.

### 8.2 DNS policy

For managed devices, DNS behavior must be controlled sufficiently for the domain-to-address-list policy to work reliably.

Codex must explicitly document:

- which DNS server managed clients use;
- whether external UDP/TCP 53 is blocked or redirected;
- whether DNS-over-HTTPS bypass is in scope or out of scope;
- any limitations of domain-based routing when a service uses CDN/shared IPs.

Do not silently assume domain routing is perfect.

---

## 9. Odoo routing

### 9.1 From ADSL workstations

ADSL workstations in `192.168.1.0/24` reach:

`192.168.1.250`

directly at Layer 2.

Changing an authorized workstation gateway from:

`192.168.1.1`

to:

`192.168.1.254`

must not break Odoo access.

### 9.2 From OmniTik managed network

Traffic path:

`192.168.88.x -> hAP -> 192.168.1.250`

The Odoo server must have the static route:

`192.168.88.0/24 via 192.168.1.254`

Expected return path:

`192.168.1.250 -> 192.168.1.254 -> 192.168.88.x`

Do not source-NAT this traffic unless required as a fallback.

The preferred design preserves original client source IPs in Odoo logs.

---

## 10. Starlink VRF return routing

Because Starlink and ADSL both use `192.168.1.0/24`, return routing must be handled explicitly.

For authorized ADSL-side Starlink clients, the Starlink VRF must contain more-specific host routes (`/32`) back toward the ADSL/main side for those clients.

Example concept:

- ADSL Starlink client:
  - `192.168.1.30/32`
- More-specific return route must override the Starlink-connected `192.168.1.0/24` route.

For the managed OmniTik network:

- `192.168.88.0/24` must have a valid return path from the Starlink VRF to the main routing domain.

Codex must explicitly implement and explain this return-path logic.

Do not generate a configuration that depends on ambiguous route leaking.

---

## 11. NAT policy

### 11.1 Starlink Internet

Internet-bound traffic leaving via Starlink should be NATed appropriately, normally using `masquerade` if the Starlink-side address is DHCP/dynamic.

### 11.2 ADSL forced domains

Traffic policy-routed through ADSL must use the correct ADSL-side source/NAT behavior.

Because ADSL clients already live on `192.168.1.0/24`, Codex must reason carefully about whether NAT is needed for each source group:

- `ADSL_STARLINK`
- `OMNI_ODOO_STARLINK`
- `OMNI_ODOO_ONLY` if domain exceptions are later allowed

Do not add broad NAT rules that accidentally hide traffic to Odoo or create asymmetric routing.

### 11.3 Odoo

No NAT between:

`192.168.88.0/24`

and:

`192.168.1.250`

under the preferred design.

---

## 12. Firewall policy

The configuration must follow a clear default-deny model for hAP-routed traffic.

At minimum:

### Input chain

Allow only required router management and infrastructure services.

Explicitly protect:

- WinBox
- SSH, if enabled
- WebFig, if enabled
- DNS service
- DHCP service
- ICMP as intentionally configured

Management access must be restricted to trusted source networks/devices.

### Forward chain

Must include:

- established/related accept;
- invalid drop;
- Odoo-specific access rules;
- forced-ADSL rules;
- authorized Starlink rules;
- explicit denial for unauthorized clients trying to use hAP as Internet gateway;
- appropriate inter-LAN restrictions;
- final deny where applicable.

Do not produce an allow-all forwarding policy.

---

## 13. DHCP administration model

For `192.168.88.0/24`, hAP should be the authoritative DHCP server.

Preferred administration workflow:

1. Administrator registers a device MAC.
2. Device receives a fixed/reserved IP.
3. Device is assigned to a logical policy group.
4. Policy group determines:
   - Odoo-only;
   - Odoo + Starlink;
   - future variants.

The final configuration must make adding/removing devices from a group simple and auditable.

Preferred structure:

- DHCP static leases
- address lists
- clear comments naming the device/user/purpose

Do not encode all device permissions as opaque one-off firewall rules.

---

## 14. Interface naming

Do not assume physical interface names beyond standard RouterOS names.

Before generating the final executable script, Codex must identify or request confirmation of:

- physical interface connected to Starlink;
- physical interface connected to ADSL LAN;
- physical interface connected to OmniTik;
- whether any hAP Wi-Fi interfaces are used;
- current bridge membership;
- existing hAP configuration that must be preserved.

Recommended logical comments/names:

- `WAN_STARLINK`
- `LAN_ADSL`
- `LAN_OMNITIK`

If interface renaming is used, it must be deliberate and documented.

---

## 15. Required inputs before final executable script

Codex must not invent these values.

Obtain or use placeholders for:

1. hAP RouterOS exact version.
2. Current `/export hide-sensitive` from hAP.
3. Interface mapping:
   - Starlink port
   - ADSL LAN port
   - OmniTik port
4. Authorized `ADSL_STARLINK` devices:
   - IP
   - MAC
   - descriptive name
5. Managed OmniTik devices:
   - MAC
   - desired fixed IP
   - group:
     - `OMNI_ODOO_ONLY`
     - `OMNI_ODOO_STARLINK`
6. Forced-ADSL domains.
7. Odoo listening ports:
   - e.g. 443, 8069, or reverse-proxy-specific ports.
8. Trusted management IPs/networks.

If a value is not supplied, Codex must leave an explicit placeholder and must not silently choose one.

---

## 16. Required deliverables from Codex

Codex must generate all of the following:

### A. Final architecture summary

Short explanation of:

- main table;
- Starlink VRF;
- overlapping subnet handling;
- Odoo route;
- DHCP policy;
- firewall policy;
- domain-based ADSL policy.

### B. Pre-change backup procedure

Include commands for:

- binary backup;
- text export;
- safe filename convention.

### C. Ordered implementation script

The script must be:

- RouterOS 7 compatible;
- ordered so dependencies exist before use;
- heavily commented;
- split into logical phases;
- safe to review before execution.

Suggested phases:

1. Safety / backups
2. Interface preparation
3. VRF creation
4. IP addressing
5. DHCP client Starlink
6. `192.168.88.0/24` DHCP server
7. Static leases / address lists
8. Routing tables / route leaking / host routes
9. DNS/domain lists
10. Policy routing
11. NAT
12. Firewall input
13. Firewall forward
14. Management restrictions
15. Validation commands

### D. Separate external changes

Do not mix these silently into hAP configuration:

- Odoo server static route
- OmniTik bridge/AP conversion
- workstation gateway changes
- DHCP reservation changes on the ADSL side if required

List each external change separately.

### E. Rollback procedure

Must explain how to recover if:

- Starlink routing fails;
- ADSL access breaks;
- OmniTik clients lose access;
- hAP management access is lost.

---

## 17. Acceptance tests

The solution is not complete until all tests below pass.

### Test 1 — normal ADSL workstation

A non-authorized ADSL workstation:

- uses gateway `192.168.1.1`;
- has ADSL Internet;
- reaches Odoo;
- does not use Starlink.

### Test 2 — unauthorized workstation tries hAP

A non-authorized ADSL workstation manually changes gateway to:

`192.168.1.254`

Expected:

- no general Starlink Internet;
- firewall logs/behavior confirm denial;
- simply knowing the gateway does not grant access.

### Test 3 — authorized ADSL Starlink workstation

An authorized `ADSL_STARLINK` workstation:

- uses `192.168.1.254`;
- reaches Odoo directly;
- general Internet uses Starlink;
- forced-ADSL domains use ADSL.

### Test 4 — OmniTik Odoo-only client

An `OMNI_ODOO_ONLY` device:

- receives its reserved `192.168.88.x` address;
- reaches `192.168.1.250`;
- cannot browse general Internet;
- cannot access unrelated ADSL hosts unless explicitly permitted.

### Test 5 — OmniTik Odoo + Starlink client

An `OMNI_ODOO_STARLINK` device:

- reaches Odoo;
- general Internet uses Starlink;
- forced-ADSL domains use ADSL.

### Test 6 — Odoo preserves client IP

For an OmniTik client accessing Odoo:

- Odoo should see the real `192.168.88.x` source address;
- not `192.168.1.254`.

### Test 7 — forced ADSL domains

For both:

- `ADSL_STARLINK`
- `OMNI_ODOO_STARLINK`

verify that configured forced domains leave through ADSL.

General destinations must continue through Starlink.

### Test 8 — overlapping subnet integrity

Verify simultaneously:

- ADSL `192.168.1.1` is reachable in main as intended.
- Starlink `192.168.1.1` is reachable in `vrf-starlink`.
- No accidental Layer 2 bridge exists between those networks.
- No ambiguous default route causes random egress.

### Test 9 — reboot persistence

After reboot:

- VRF is correct;
- DHCP servers/clients recover;
- routes recover;
- address lists recover as designed;
- policies remain functional.

---

## 18. Non-goals

Do not implement unless explicitly requested later:

- load balancing between ADSL and Starlink;
- automatic failover between both WANs;
- changing ADSL LAN addressing;
- changing Starlink LAN addressing;
- Starlink bypass mode;
- path-specific HTTPS URL routing;
- captive portal;
- per-user authentication;
- 802.1X;
- VLAN redesign;
- replacement of the unmanaged ADSL switch.

---

## 19. Configuration quality requirements

The generated configuration must:

- be deterministic;
- avoid unnecessary complexity;
- preserve existing service where possible;
- use clear comments;
- avoid duplicate/conflicting rules;
- avoid FastTrack if it would bypass policy routing/VRF behavior, or explicitly redesign FastTrack safely;
- avoid broad masquerade rules that break Odoo source visibility;
- avoid rules that grant Starlink merely because the source uses `192.168.1.254`;
- avoid relying on rule order that is not documented;
- be auditable by another network administrator.

If FastTrack is currently enabled, Codex must specifically analyze its interaction with policy routing before preserving it.

---

## 20. Canonical policy summary

The intended end state is:

```text
ADSL network
192.168.1.0/24
    |
    +-- 192.168.1.1  ADSL gateway
    |
    +-- 192.168.1.250 Odoo
    |
    +-- 192.168.1.254 hAP policy gateway
            |
            +-- authorized ADSL clients -> Starlink
            |      except FORCE_ADSL domains -> ADSL
            |
            +-- unauthorized ADSL clients -> no hAP Internet forwarding
            |
            +-- 192.168.88.0/24 managed LAN
            |      |
            |      +-- OMNI_ODOO_ONLY
            |      |      -> Odoo only
            |      |
            |      +-- OMNI_ODOO_STARLINK
            |             -> Odoo + Starlink
            |             -> FORCE_ADSL domains through ADSL
            |
            +-- vrf-starlink
                   |
                   +-- Starlink router
                       192.168.1.1/24
```

---

## 21. Instruction to Codex

Treat this document as the canonical source of truth.

Do not simplify away:

- the overlapping `192.168.1.0/24` networks;
- the VRF requirement;
- the security requirement that `.254` alone grants nothing;
- the Odoo static-route design;
- the `192.168.88.0/24` managed network;
- the device-group administration model;
- the forced-ADSL domain policy.

Before writing the final executable configuration:

1. inspect the current hAP export;
2. map actual interfaces;
3. identify existing rules that conflict with this design;
4. present any required deviations;
5. only then generate the final RouterOS 7 script.

Do not guess missing production values.

