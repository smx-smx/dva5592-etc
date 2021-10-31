#!/bin/sh
[ "$user" = "USER_SKIP_EXEC" ] && exit 0
if [ "$#" -eq "1" ] && [ "$op" = "d" ]; then
	for r in QoS.Queue QoS.Classification QoS.Shaper NAT.InterfaceSetting NAT.PortMapping DHCPv4.Server.Pool X_ADB_VPN.Client.PPTP X_ADB_VPN.Client.L2TP DNS.Client.Server Device.DNS.Relay.Forwarding RouterAdvertisement.InterfaceSetting Device.NeighborDiscovery.InterfaceSetting Device.Routing.RIP.InterfaceSetting; do
		cmclient -v o GETO "$r.[Interface=$obj]"
		for o in $o; do
			cmclient SET "$o.Enable" false
			cmclient SET "$o.Interface" ""
			[ "$r" = "Device.DNS.Relay.Forwarding" ] && cmclient SET "$o.X_ADB_InboundInterface" ""
		done
		if [ "$r" = "Device.DNS.Relay.Forwarding" ]; then
			cmclient -v o GETO "$r.[X_ADB_InboundInterface=$obj]"
			for o in $o; do
				cmclient SET "$o.Enable" false
				cmclient SET "$o.Interface" ""
				cmclient SET "$o.X_ADB_InboundInterface" ""
			done
		fi
	done
	cmclient -v r GETO "Device.Firewall.Chain.Rule.[SourceInterface=$obj]"
	for r in $r; do
		cmclient SET "$r.SourceInterface" ""
	done
	cmclient -v r GETO "Device.Firewall.Chain.Rule.[DestInterface=$obj]"
	for r in $r; do
		cmclient SET "$r.DestInterface" ""
	done
	/etc/ah/Firewall.sh ifchange "$obj"
	/etc/ah/TR069.sh "ipifdel" "$obj"
	/etc/ah/PPPoEProxy.sh "ipifdel" "$obj"
fi
exit 0
