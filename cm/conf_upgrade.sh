#!/bin/sh
. /etc/ah/helper_conf_upgrade.sh
upgrade_6_0_0_0026() {
cmclient SETE "Device.Services.VoiceService.1.X_ADB_SIP.SupportViaRPort" "true"
cmclient SETE "Device.Users.X_ADB_DefaultPasswordCheck" "true"
cmclient DELE "Device.Services.X_ADB_DynamicDNS.Provider"
cmclient CONF /etc/cm/conf/factory_ddns.xml
cmclient CONF /etc/cm/conf/factory_ddns_dlink.xml
cmclient SETE "Device.X_ADB_ParentalControl.ShowLinkOnLogin" "false"
cmclient SETE "Device.Users.X_ADB_PasswordMinLength" 8
cmclient SETE "Device.Users.X_ADB_PasswordEnforcementRules" "OneDigit,OneUppercaseLetter,OneLowercaseLetter"
}
checkupgrade_6_0_0_0026() {
return
}
downgrade_6_0_0_0026() {
return
}
checkdowngrade_6_0_0_0026() {
return
}
upgrade_6_0_0_0024() {
cmclient CONF /etc/cm/conf/factory_failover.xml
cmclient SETE "Device.UserInterface.X_ADB_AccessControl.Feature.[PagePath=clish/system/upgrade/secureDevice].Permissions" "0000"
cmclient CONF /etc/cm/conf/factory_DNS.xml
cmclient DELE Device.X_ADB_LED.ServiceLED
cmclient CONF /etc/cm/conf/factory_led.xml
return
}
checkupgrade_6_0_0_0024() {
return
}
downgrade_6_0_0_0024() {
return
}
checkdowngrade_6_0_0_0024() {
return
}
upgrade_6_0_0_0023() {
local idx mod p
mod="Device.X_ADB_MobileModem.Model"
cmclient -v idx ADDE "$mod.[Name=MF833V]"
p="${mod}.${idx}.Enable=true"
p="${p}	${mod}.${idx}.Manufacturer=ZTE"
p="${p}	${mod}.${idx}.VendorID=6610"
p="${p}	${mod}.${idx}.ProductID=5153"
p="${p}	${mod}.${idx}.TargetVendorID=6610"
p="${p}	${mod}.${idx}.TargetProductIDs=4738"
cmclient SETEM "${p}"
cmclient DELE Device.X_ADB_LED.ServiceLED
cmclient CONF /etc/cm/conf/factory_led.xml
cmclient SETE "Device.X_ADB_InterfaceMonitor.Group.1.Interface.1.Name" "DSL Interface"
cmclient SETE "Device.X_ADB_InterfaceMonitor.Group.1.Interface.1.Priority" "3"
cmclient SETE "Device.X_ADB_InterfaceMonitor.Group.1.Interface.2.Priority" "2"
cmclient SETE "Device.X_ADB_InterfaceMonitor.Group.1.Interface.3.Priority" "1"
cmclient SETE "Device.X_ADB_InterfaceMonitor.Group.1.Interface.4.Priority" "10"
cmclient SETE "Device.X_ADB_InterfaceMonitor.Group.1.Interface.4.StartupTimeout" "60"
cmclient SETE "Device.X_ADB_LED.ServiceLED.3.Behaviour.1.Trigger.1.Operator" "NotEmpty"
cmclient SETE "Device.X_ADB_LED.ServiceLED.3.Behaviour.1.Trigger.1.Parameter" "Device.PPP.Interface.1.IPCP.LocalIPAddress"
cmclient SETE "Device.X_ADB_LED.ServiceLED.3.Behaviour.1.Trigger.1.Value" ""
cmclient SETE "Device.Services.VoiceService.1.VoiceProfile.Line.Codec.List.[Codec=G.729].SilenceSuppression" "false"
return
}
checkupgrade_6_0_0_0023() {
return
}
downgrade_6_0_0_0023() {
return
}
checkdowngrade_6_0_0_0023() {
return
}
upgrade_6_0_0_0022() {
local setm idx mobile_modem_idx ppp_idx ethernet_link_idx group_idx interface_idx action_idx
cmclient -v idx ADDE Device.UserInterface.X_ADB_AccessControl.Feature
setm="Device.UserInterface.X_ADB_AccessControl.Feature.$idx.PagePath=clish/system/customerDefault EnableButtonbackToFactory"
setm="$setm	Device.UserInterface.X_ADB_AccessControl.Feature.$idx.Permissions=0000"
cmclient SETEM "$setm"
cmclient SETE "Device.UserInterface.X_ADB_AccessControl.Feature.[PagePath=dboard/settings/interface-failover].Permissions" "1001"
cmclient SETE "Device.UserInterface.X_ADB_AccessControl.Feature.[PagePath=clish/configure/managment/webGui].PagePath" "clish/configure/management/webGui"
cmclient SETE "Device.UserInterface.X_ADB_AccessControl.Feature.[PagePath=clish/configure/management/webGui].Permissions" "0000"
cmclient SETE "Device.UserInterface.X_ADB_AccessControl.Feature.[PagePath=clish/configure/managment/users].PagePath" "clish/configure/management/users"
cmclient SETE "Device.UserInterface.X_ADB_AccessControl.Feature.[PagePath=clish/configure/managment/telnetServer].PagePath" "clish/configure/management/telnetServer"
cmclient SETE "Device.UserInterface.X_ADB_AccessControl.Feature.[PagePath=clish/configure/managment/tr069Agent].PagePath" "clish/configure/management/tr069Agent"
cmclient SETE "Device.UserInterface.X_ADB_AccessControl.Feature.[PagePath=clish/configure/managment/sshServer].PagePath" "clish/configure/management/sshServer"
cmclient -v idx ADDE "Device.X_ADB_MobileModem.Model"
setm="Device.X_ADB_MobileModem.Model.$idx.Enable=true"
setm="$setm	Device.X_ADB_MobileModem.Model.$idx.Name=DWM-157"
setm="$setm	Device.X_ADB_MobileModem.Model.$idx.Manufacturer=D-Link"
setm="$setm	Device.X_ADB_MobileModem.Model.$idx.VendorID=8193"
setm="$setm	Device.X_ADB_MobileModem.Model.$idx.ProductID=41991"
setm="$setm	Device.X_ADB_MobileModem.Model.$idx.TargetVendorID=8193"
setm="$setm	Device.X_ADB_MobileModem.Model.$idx.TargetProductIDs=32014"
setm="$setm	Device.X_ADB_MobileModem.Model.$idx.TargetInterfaceClass=0"
setm="$setm	Device.X_ADB_MobileModem.Model.$idx.MessageContents=555342431234567800000000000003f0010300000000000000000000000000"
cmclient -v idx ADDE "Device.X_ADB_MobileModem.Model"
setm="$setm	Device.X_ADB_MobileModem.Model.$idx.Enable=true"
setm="$setm	Device.X_ADB_MobileModem.Model.$idx.Name=DWM-222"
setm="$setm	Device.X_ADB_MobileModem.Model.$idx.Manufacturer=D-Link"
setm="$setm	Device.X_ADB_MobileModem.Model.$idx.VendorID=8193"
setm="$setm	Device.X_ADB_MobileModem.Model.$idx.ProductID=43776"
setm="$setm	Device.X_ADB_MobileModem.Model.$idx.TargetVendorID=8193"
setm="$setm	Device.X_ADB_MobileModem.Model.$idx.TargetProductIDs=32309"
setm="$setm	Device.X_ADB_MobileModem.Model.$idx.TargetInterfaceClass=0"
setm="$setm	Device.X_ADB_MobileModem.Model.$idx.MessageContents=5553424378563412010000008000061b446576696e00000000000000000000"
cmclient SETEM "$setm"
cmclient CONF /etc/cm/conf/factory_X_ADB_MobileModem.xml
cmclient CONF /etc/cm/conf/factory_failover.xml
cmclient CONF /etc/cm/conf/factory_NAT.xml
cmclient DELE "Device.InterfaceStack"
/etc/ah/InterfaceStack.sh init
cmclient SETE "Device.UserInterface.X_ADB_AccessControl.Feature.[PagePath=clish/system/upgrade/fw_upgr_permitted].Permissions" "0000"
return
}
checkupgrade_6_0_0_0022() {
return
}
downgrade_6_0_0_0022() {
cmclient DELE Device.X_ADB_LED.ServiceLED
cmclient CONF /etc/cm/conf/factory_led.xml
}
checkdowngrade_6_0_0_0022() {
return
}
upgrade_6_0_0_0021() {
local setm
setm="Device.WiFi.SSID.3.SSID=D-Link-Guest"
setm="$setm	Device.WiFi.SSID.4.SSID=D-Link-Guest"
setm="$setm	Device.WiFi.AccessPoint.3.X_ADB_APIsolation=true"
setm="$setm	Device.WiFi.AccessPoint.4.X_ADB_APIsolation=true"
setm="$setm	Device.WiFi.AccessPoint.3.X_ADB_WirelessSegregation=true"
setm="$setm	Device.WiFi.AccessPoint.4.X_ADB_WirelessSegregation=true"
cmclient SETEM "$setm"
return
}
checkupgrade_6_0_0_0021() {
return
}
downgrade_6_0_0_0021() {
return
}
checkdowngrade_6_0_0_0021() {
return
}
upgrade_6_0_0_0019() {
local clsorder=""
cmclient DELE "Device.QoS.Classification.[Alias=WAN_DATA_MARK]"
cmclient -v clsorder GETV Device.QoS.Classification.[ForwardingPolicy="1004"].Order
[ "$clsorder" = "10" ] && cmclient SETE Device.QoS.Classification.[Order="$clsorder"].Order "9"
}
checkupgrade_6_0_0_0019() {
return
}
downgrade_6_0_0_0019() {
return
}
checkdowngrade_6_0_0_0019() {
return
}
upgrade_6_0_0_0018() {
local im_obj="" setm act_no j
cmclient -v im_obj GETO Device.X_ADB_InterfaceMonitor.Group.Interface.[Name="Fiber Interface"]
if [ -n "$im_obj" ]; then
cmclient SETE "$im_obj".HysteresisUp "30"
for j in 1 2; do
cmclient -v act_no ADDE "$im_obj".Action
setm="$im_obj.Action.$act_no.Path=Device.PPP.Interface.$j.Reset"
setm="$setm	$im_obj.Action.$act_no.Event=Up"
setm="$setm	$im_obj.Action.$act_no.Value=true"
cmclient SETEM "$setm"
done
fi
}
checkupgrade_6_0_0_0018() {
return
}
downgrade_6_0_0_0018() {
local clsid=""
cmclient -v clsid ADDE Device.QoS.Classification.[Enable="false"].[Alias="WAN_DATA_MARK"].[EthernetPriorityMark="1"].[Interface="Device.PPP.Interface.1"].[X_ADB_InterfaceType="Egress"]
[ -n "$clsid" ] && cmclient SETE Device.QoS.Classification.${clsid}.Order "$clsid"
return
}
checkdowngrade_6_0_0_0018() {
return
}
upgrade_6_0_0_0016() {
local eln conn_id eth_link
cmclient -v eln GETO "Device.Ethernet.Link.[LowerLayers=Device.Ethernet.Interface.6]"
case "$eln" in
*Device.Ethernet.Link.9*)
;;
*)
. /etc/ah/helper_tr098.sh
. /etc/ah/TR098_AlignAll.sh
cmclient ADDE Device.Ethernet.Link.9
setm="Device.Ethernet.Link.9.LowerLayers=Device.Ethernet.Interface.6"
setm="$setm	Device.Ethernet.Link.9.Alias=Link9"
setm="$setm	Device.Ethernet.Link.9.Enable=true"
setm="$setm	Device.Ethernet.Link.9.Name=eth0"
cmclient SETEM "$setm"
cmclient SETE "Device.Ethernet.VLANTermination.5.LowerLayers Device.Ethernet.Link.9"
cmclient DELE "Device.InterfaceStack"
/etc/ah/InterfaceStack.sh init
help98_destroy_wanconnection "2"
cmclient -v eth_link GETO "Device.Ethernet.Link.*.[LowerLayers=Device.Ethernet.Interface.6]"
for eth_link in $eth_link; do
conn_id=`help181_add_tr98obj "$OBJ_IGD.WANDevice.2.WANConnectionDevice"`
help98_add_xan_xconfig "$OBJ_IGD.WANDevice.2.WANConnectionDevice.$conn_id.WANEthernetLinkConfig" "$eth_link" "EthernetLink$eth_link"
help98_build_wan_ip_ppp "$eth_link" "$OBJ_IGD.WANDevice.2.WANConnectionDevice.$conn_id" "EthernetLink" "WANEthernetLinkConfig"
done
;;
esac
cmclient SETE "Device.WiFi.Radio.2.X_ADB_ZeroWaitDFSEnable true"
cmclient SETE "Device.WiFi.Radio.2.X_ADB_ZeroWaitDFSSupported true"
return
}
checkupgrade_6_0_0_0016() {
return
}
downgrade_6_0_0_0016() {
return
}
checkdowngrade_6_0_0_0016() {
return
}
upgrade_6_0_0_0015() {
local setm obj_num
cmclient CONF /etc/cm/conf/factory_scheduler.xml
setm="Device.WiFi.Radio.1.X_ADB_TimeSchedulerEnable=true"
setm="$setm	Device.WiFi.Radio.1.X_ADB_TimeScheduler=Device.X_ADB_Time.Scheduler.Profile.1"
cmclient SETEM "$setm"
setm="Device.WiFi.Radio.2.X_ADB_TimeSchedulerEnable=true"
setm="$setm	Device.WiFi.Radio.2.X_ADB_TimeScheduler=Device.X_ADB_Time.Scheduler.Profile.2"
cmclient SETEM "$setm"
cmclient CONF /etc/cm/conf/factory_optical.xml
cmclient SETE "Device.Services.X_ADB_DynamicDNS.Provider.8.Name dlinkddns.com"
setm="Device.WiFi.X_ADB_BandSteering.Enable=true"
setm="$setm	Device.WiFi.X_ADB_BandSteering.DualBandDetectionEnable=true"
cmclient SETEM "$setm"
cmclient SETE "Device.DeviceInfo.X_DLINK_BsdGuiVisible true"
cmclient SETE "Device.DeviceInfo.X_ADB_UpgradeFilename DVA-5592_A1_WI.sig"
cmclient SETE "Device.WiFi.Radio.2.X_ADB_UseE0Rev938RegulatoryDomain true"
setm="Device.WiFi.X_ADB_BandSteering.RssiThreshold5=-100"
setm="$setm	Device.WiFi.X_ADB_BandSteering.RssiThreshold24=-70"
cmclient SETEM "$setm"
cmclient -v obj_num ADDE "Device.UserInterface.X_ADB_AccessControl.Feature"
setm="Device.UserInterface.X_ADB_AccessControl.Feature.$obj_num.PagePath=dboard/settings/voip/commonnumberingplan"
setm="$setm	Device.UserInterface.X_ADB_AccessControl.Feature.$obj_num.Permissions=0000"
cmclient SETEM "$setm"
cmclient -v obj_num ADDE "Device.X_ADB_InterfaceMonitor.Group.1.Interface.1.Action.[Path=Device.Services.VoiceService.1.X_DLINK_Enable]"
setm="Device.X_ADB_InterfaceMonitor.Group.1.Interface.1.Action.$obj_num.Event=Up"
setm="$setm	Device.X_ADB_InterfaceMonitor.Group.1.Interface.1.Action.$obj_num.Value=false"
cmclient SETEM "$setm"
cmclient -v obj_num ADDE "Device.X_ADB_InterfaceMonitor.Group.1.Interface.2.Action.[Path=Device.Services.VoiceService.1.X_DLINK_Enable]"
setm="Device.X_ADB_InterfaceMonitor.Group.1.Interface.2.Action.$obj_num.Event=Up"
setm="$setm	Device.X_ADB_InterfaceMonitor.Group.1.Interface.2.Action.$obj_num.Value=false"
cmclient SETEM "$setm"
cmclient -v obj_num ADDE "Device.X_ADB_InterfaceMonitor.Group.1.Interface.3.Action.[Path=Device.Services.VoiceService.1.X_DLINK_Enable]"
setm="Device.X_ADB_InterfaceMonitor.Group.1.Interface.3.Action.$obj_num.Event=Up"
setm="$setm	Device.X_ADB_InterfaceMonitor.Group.1.Interface.3.Action.$obj_num.Value=false"
cmclient SETEM "$setm"
cmclient ADDE Device.X_ADB_LED.ServiceLED.2.Behaviour.4
setm="Device.X_ADB_LED.ServiceLED.2.Behaviour.4.Colour=Green"
setm="$setm	Device.X_ADB_LED.ServiceLED.2.Behaviour.4.DutyCycle=On"
cmclient SETEM "$setm"
cmclient ADDE Device.X_ADB_LED.ServiceLED.2.Behaviour.4.Trigger.1
setm="Device.X_ADB_LED.ServiceLED.2.Behaviour.4.Trigger.1.Operator=CountObj_>"
setm="$setm	Device.X_ADB_LED.ServiceLED.2.Behaviour.4.Trigger.1.Parameter=Device.Ethernet.Interface.[Upstream=true].[Status=Up]"
setm="$setm	Device.X_ADB_LED.ServiceLED.2.Behaviour.4.Trigger.1.Value=0"
cmclient SETEM "$setm"
cmclient ADDE Device.X_ADB_LED.ServiceLED.2.Behaviour.5
setm="Device.X_ADB_LED.ServiceLED.2.Behaviour.5.Colour=Green"
setm="$setm	Device.X_ADB_LED.ServiceLED.2.Behaviour.5.DutyCycle=Off"
cmclient SETEM "$setm"
cmclient ADDE Device.X_ADB_LED.ServiceLED.2.Behaviour.5.Trigger.1
setm="Device.X_ADB_LED.ServiceLED.2.Behaviour.5.Trigger.1.Operator=CountObj_>"
setm="$setm	Device.X_ADB_LED.ServiceLED.2.Behaviour.5.Trigger.1.Parameter=Device.Ethernet.Interface.[Upstream=true]"
setm="$setm	Device.X_ADB_LED.ServiceLED.2.Behaviour.5.Trigger.1.Value=0"
cmclient SETEM "$setm"
return
}
checkupgrade_6_0_0_0015() {
return
}
downgrade_6_0_0_0015() {
local im_obj=""
cmclient -v im_obj GETO Device.X_ADB_InterfaceMonitor.Group.Interface.[Name="Fiber Interface"]
if [ -n "$im_obj" ]; then
cmclient SETE "$im_obj".HysteresisUp "0"
cmclient DELE "$im_obj".Action.[Path="Device.PPP.Interface.1.Reset"]
cmclient DELE "$im_obj".Action.[Path="Device.PPP.Interface.2.Reset"]
fi
return
}
checkdowngrade_6_0_0_0015() {
return
}
if [ "$4" != "check" ]; then
echo "Previous version: $1" > /dev/console
echo "Current version: $2" > /dev/console
fi
doUpgrade "$@"
