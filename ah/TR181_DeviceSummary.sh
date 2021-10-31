#!/bin/sh
. /etc/ah/helper_device_summary.sh
base="Baseline:2, \
ADSL:1, \
ADSL2:2, \
AdvancedFirewall:1, \
ATMLink:1, ATMLoopback:1, \
Bridge:1, BridgeFilter:2, BridgeL3L4Filter:1, \
DeviceAssociation:1, \
DHCPv4Client:1, DHCPv4CondServing:1, DHCPv4Relay:1, \
DHCPv4Server:1, DHCPv4ServerClientInfo:1, \
DNSRelay:1, \
Download:1, DownloadTCP:1, \
EthernetInterface:2, EthernetLink:1, \
Hosts:2, \
IPInterface:2, \
IPPing:1, \
MemoryStatus:1, \
NAT:1, \
NSLookupDiag:1, \
PPPInterface:1, \
ProcessStatus:1, \
QoS:2, QoSDynamicFlow:1, QoSStats:1, \
Routing:2, \
Time:1, \
TraceRoute:1, \
Upload:1, UploadTCP:1, \
USBHostsBasic:1, \
USBInterface:1, USBPort:1, \
User:1, \
VLANBridge:1, VLANTermination:1, \
WiFiAccessPoint:1, WiFiEndPoint:1, WiFiRadio:1, WiFiSSID:1"
help_check_profile addon "BondedDSL:1" "Device.DSL.BondingGroupNumberOfEntries"
help_check_profile addon "CaptivePortal:1" "Device.CaptivePortal.Enable"
help_check_profile addon "DHCPv6Client:1, DHCPv6ClientServerIdentity:1" "Device.DHCPv6.ClientNumberOfEntries"
help_check_profile addon "DHCPv6Server:1, DHCPv6ServerAdv:1, DHCPv6ServerClientInfo:1" "Device.DHCPv6.Server.PoolNumberOfEntries"
help_check_profile addon "HPNA:1" "Device.HPNA.InterfaceNumberOfEntries"
help_check_profile addon "IPsec:1" "Device.IPsec.ProfileNumberOfEntries"
help_check_profile addon "IPv6Interface:1" "Device.IP.IPv6Capable"
help_check_profile addon "IPv6rd:1" "Device.IPv6rd.InterfaceSettingNumberOfEntries"
help_check_profile addon "IPv6Routing:1" "Device.Routing.Router.*.IPv6ForwardingNumberOfEntries"
help_check_profile addon "NeighborDiscovery:1" "Device.NeighborDiscovery.InterfaceSettingNumberOfEntries"
help_check_profile addon "PPPInterface:2" "Device.PPP.SupportedNCPs"
help_check_profile addon "PTMLink:1" "Device.PTM.LinkNumberOfEntries"
help_check_profile addon "RouterAdvertisement:1" "Device.RouterAdvertisement.InterfaceSettingNumberOfEntries"
help_check_profile addon "SM_Baseline:1, SM_ExecEnvs:1, SM_DeployAndExecUnits:1" "Device.SoftwareModules.ExecEnvNumberOfEntries"
help_check_profile addon "UDPConnReq:1" "Device.ManagementServer.UDPConnectionRequestAddress"
help_check_profile addon "UDPEcho:1, UDPEchoPlus:1" "Device.IP.Diagnostics.UDPEchoConfig.Enable"
help_check_profile addon "UPnPDev:1" "Device.UPnP.Device.Enable"
help_check_profile addon "VDSL2:1" "Device.DSL.Line.*.AllowedProfiles"
help_check_profile addon "VDSL2:1" "Device.DSL.Line.*.X_ADB_AllowedProfiles"
summary="Device:2.8[](${base}${addon:+, $addon})"
help_tr104_summary Device summary
help_tr140_summary Device summary
cmclient SETE Device.DeviceSummary "$summary"
exit 0
