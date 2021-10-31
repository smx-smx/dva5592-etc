#!/bin/sh
outdir="/tmp"
modules="
device
main
apps
bluetooth
dlna
ipv6
upnp
vdsl
voip
vpn
"
ignored_dm="
LAN-DHCP
LAN-Ethernet
LAN-Interfaces
LAN-USB
LAN-WiFi
IPDiagnostics
Diagnostics-ADSL
Diagnostics-IP
NeighborDiscovery
RouterAdvertisement
Diagnostics-VDSL
WAN
WAN-ADSL
WAN-Ethernet
WAN-PTM
WAN-VDSL2
"
device_dm="
Device
T01_NestedCalls
TR069
"
main_dm="
Routing-Bridging
NTP
WiFi
PPPoE-Proxy
IGMP-Proxy
StorageService
PrinterService
RTSP-Proxy
DSL
SystemLogMgmt
QoS
Ethernet
ParentalControl
PPP
NAT
Management
IP
Firewall
DNS
DMZ
DHCP-Client
DHCP-Server
CaptivePortal
ATM
Storage-FTP
Storage-HTTP
Storage-SFTP
Storage-SMART
USB
"
apps_dm="
SoftwareModules
"
bluetooth_dm="
Bluetooth
"
dlna_dm="
DLNA
"
ipv6_dm="
DSLite
IP_IPv6_Integration
IPv6rd
PPP_IPv6_Integration
Routing_IPv6_Integration
"
led_dm="
LED
"
upnp_dm="
UPnP
"
vdsl_dm="
PTM
VDSL
"
voip_dm="
VoiceService
"
vpn_dm="
VPN-Users
PPTP-Client
PPTP-Server
L2TP-Client
L2TP-Server
IPSec-Client
IPSec-Server
"
xmlheader='<?xml version="1.0" encoding="UTF-8"?>'
while [ -n "$1" ]; do
case "$1" in
-d )
shift
outdir="$1"
shift
;;
--outdir=* )
outdir="${1##=*}"
shift
;;
* )
echo "Ignoring option $1."
shift
;;
esac
done
for module in ${modules}; do
ofile="${outdir}/factory_${module}.xml"
echo "Generating $ofile"
rm -rf ${ofile}
echo "${xmlheader}" > ${ofile}
eval dms="\$${module}_dm"
for dm in $dms; do
echo -n "	Exporting... datamodel $dm..."
tmpfile=`mktemp`
cmclient EXPORTDM $dm $tmpfile > /dev/null
cat $tmpfile | grep -v "${xmlheader}" | grep -Ev "^$" >> ${ofile}
rm $tmpfile
echo " done."
done
done
