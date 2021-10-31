#!/bin/sh
. /etc/ah/helper_device_summary.sh
base="Baseline:2, \
ADSLWAN:1, ADSL2WAN:1, \
ATMLoopback:1, \
Bridging:2, BridgingPortVLAN:1, \
DeviceAssociation:1, \
DHCPCondServing:1, DHCPOption:1, \
Download:1, DownloadTCP:1, \
EthernetLAN:2, EthernetWAN:1, \
IPPing:1, \
QoS:2, QoSDynamicFlow:2, QoSStats:1, \
SimpleFirewall:1, \
Time:2, \
TraceRoute:1, \
Upload:1, UploadTCP:1, \
USBLAN:2, \
User:1, \
WiFiLAN:2, WiFiWPS:1"
help_check_profile addon "CaptivePortal:1" "InternetGatewayDevice.CaptivePortal.Enable"
help_check_profile addon "UDPConnReq:1" "InternetGatewayDevice.ManagementServer.UDPConnectionRequestAddress"
help_check_profile addon "UDPEcho:1, UDPEchoPlus:1" "InternetGatewayDevice.UDPEchoConfig.Enable"
help_check_profile addon "VDSL2WAN:1, PTMWAN:1" "InternetGatewayDevice.WANDevice.*.WANDSLInterfaceConfig.AllowedProfiles"
help_check_profile addon "SM_Baseline:1, SM_ExecEnvs:1, SM_DeployAndExecUnits:1" "InternetGatewayDevice.SoftwareModules.ExecEnvNumberOfEntries"
summary="InternetGatewayDevice:1.4[](${base}${addon:+, $addon})"
help_tr104_summary InternetGatewayDevice summary
help_tr140_summary InternetGatewayDevice summary
cmclient SETE InternetGatewayDevice.DeviceSummary "$summary"
exit 0
