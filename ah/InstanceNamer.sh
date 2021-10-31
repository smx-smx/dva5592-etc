#!/bin/sh
case "$obj" in
Device.ATM.Link.*)
	suffix=$((${obj##*.} - 1))
	cmclient SET -u "ATMLink$obj" "$obj".Name "atm$suffix" >/dev/null
	;;
Device.Bridging.Bridge.*.Port.*)
	parent=${obj%%.Port.*}
	suffix=$((${parent##*.} - 1))
	if [ "$(cmclient GETV "$obj".ManagementPort)" = "true" ]; then
		cmclient SET -u "BridgingBridge$obj" "$obj".Name "br$suffix" >/dev/null
	else
		cmclient SET -u "BridgingBridge$obj" "$obj".Name "" >/dev/null
	fi
	;;
Device.DSL.BondingGroup.*)
	suffix=$((${obj##*.} - 1))
	cmclient SET -u "DslBonding$obj" "$obj".Name "bond$suffix" >/dev/null
	;;
Device.DSL.Channel.*)
	suffix=$((${obj##*.} - 1))
	cmclient SET -u "DslChannel$obj" "$obj".Name "chan$suffix" >/dev/null
	;;
Device.DSL.Line.*)
	suffix=$((${obj##*.} - 1))
	cmclient SET -u "DslLine$obj" "$obj".Name "dsl$suffix" >/dev/null
	;;
Device.Ethernet.Interface.*)
	suffix=$((${obj##*.} - 1))
	cmclient SET -u "EthernetIf$obj" "$obj".Name "eth$suffix" >/dev/null
	;;
Device.Ethernet.Link.*)
	cmclient -v currentName GETV "$obj".Name
	[ "wwan0" != "$currentName" ] && cmclient SET -u "EthernetLink$obj" "$obj".Name "$(cmclient GETV "$newLowerLayers".Name)" >/dev/null
	;;
Device.Ethernet.VLANTermination.*)
	: ${newLowerLayers:=$(cmclient GETV "$obj".LowerLayers)}
	: ${newVLANID:=$(cmclient GETV "$obj".VLANID)}
	[ -n "$newLowerLayers" -a -n "$newVLANID" ] &&
		cmclient SET -u "EthernetVLAN$obj" "$obj".Name "$(cmclient GETV "$newLowerLayers".Name).$newVLANID" >/dev/null
	;;
Device.IP.Interface.*)
	suffix=$((${obj##*.} - 1))
	cmclient SET -u "IPIf$obj" "$obj".Name "ip$suffix" >/dev/null
	;;
Device.PPP.Interface.*)
	suffix=$((${obj##*.} - 1))
	cmclient SET -u "PPPIf$obj" "$obj".Name "ppp$suffix" >/dev/null
	;;
Device.PTM.Link*)
	suffix=$((${obj##*.} - 1))
	cmclient SET -u "PTMLink$obj" "$obj".Name "ptm$suffix" >/dev/null
	;;
Device.WiFi.Radio.*)
	suffix=$((${obj##*.} - 1))
	cmclient SET -u "WiFiRadio$obj" "$obj".Name "wl$suffix" >/dev/null
	;;
Device.WiFi.SSID.*)
	cmclient -v radioName GETV "$newLowerLayers.Name"
	cmclient -v baseSSID GETO "Device.WiFi.SSID.[Name=$radioName]"
	if [ -z "$baseSSID" ]; then
		cmclient SET -u "WiFiSSID$obj" "$obj".Name "$radioName"
	else
		count=$(cmclient GETO "Device.WiFi.SSID.[LowerLayers=$newLowerLayers]" | wc -l)
		cmclient SET -u "WiFiSSID$obj" "$obj".Name "${radioName}.$((count - 1))"
	fi
	;;
Device.X_ADB_VPN.Client.L2TP.*)
	suffix=$((${obj##*.} - 1))
	cmclient SETE "$obj".Name "l2tp$suffix"
	;;
Device.X_ADB_VPN.Client.PPTP.*)
	suffix=$((${obj##*.} - 1))
	cmclient SETE "$obj".Name "pptp$suffix"
	;;
esac
exit 0
