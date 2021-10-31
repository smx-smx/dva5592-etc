#!/bin/sh
. /etc/ah/helper_ifname.sh
if [ "$1" = "reset" ]; then
	{
		cmclient SET Ethernet.Interface.+.Stats.X_ADB_Reset true
		cmclient SET WiFi.SSID.+.Stats.X_ADB_Reset true
		cmclient SET Bridging.Bridge.+.Stats.X_ADB_Reset true
		cmclient SET Ethernet.VLANTermination.+.Stats.X_ADB_Reset true
		cmclient SET PPP.Interface.+.Stats.X_ADB_Reset true
		cmclient SET PTM.Link.+.Stats.X_ADB_Reset true
		cmclient SET ATM.Link.+.Stats.X_ADB_Reset true
		for i in 0 1 2 3 4; do
			ethswctl -c clearstat -p $i
		done
	} >/dev/null 2>&1
	exit 0
fi
if [ "$1" = "all" ]; then
	ifObjects="Device.Bridging.Bridge.Port.[ManagementPort=true] Device.Ethernet.Interface Device.Ethernet.VLANTermination Device.PPP.Interface Device.WiFi.SSID"
else
	ifObjects=$1
fi
for objectType in $ifObjects; do
	cmclient -v objectInstances GETO $objectType
	for singleObject in $objectInstances; do
		help_lowlayer_ifname_get a $singleObject
		printf "-------- Driver Statistics --------\n"
		printf "Device name: %s\n" "$a"
		if [ "$objectType" = Device.Ethernet.Interface ]; then
			cmclient -v upstream GETV $singleObject.Upstream
		else
			case $a in
			ptm*)
				upstream=true
				;;
			atm*)
				upstream=true
				;;
			dsl*)
				upstream=true
				;;
			ppp*)
				upstream=true
				;;
			eth*.*)
				upstream=true
				;;
			*)
				upstream=false
				;;
			esac
		fi
		if [ "$upstream" = true ]; then
			printf "Network = WAN\n"
		else
			printf "Network = LAN\n"
		fi
		cmclient -v status GETV $singleObject.Status
		printf "Port status = $status\n"
		cmclient -v statistics GET $singleObject.Stats.
		for singleStatLine in $statistics; do
			par=${singleStatLine##*.}
			par=${par%;*}
			parVal=${singleStatLine##*;}
			[ "$par" != X_ADB_Reset -a -n "$parVal" ] && printf "\t%-30s%-10s\n" "$par:" "$parVal"
		done
		printf "\n"
	done
done
