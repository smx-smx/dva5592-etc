#!/bin/sh
AH_NAME="ServicesReconf"
[ "$user" = "eh_ipv6" ] && exit 0
[ "$user" = "${AH_NAME}" ] && exit 0
. /etc/ah/helper_firewall.sh
. /etc/ah/IPv6_helper_firewall.sh
. /etc/ah/helper_functions.sh
. /etc/ah/helper_ifname.sh
. /etc/ah/helper_provisioning.sh
. /etc/ah/helper_ifmonitor.sh
IPServices() {
	local is_managed IPObject
	IPObject="${obj%%.IPv[46]Address*}"
	cmclient -v is_managed GETO "Device.X_ADB_InterfaceMonitor.[Enable=true].Group.[Enable=true].*.Interface.[MonitoredInterface=${IPObject}]"
	if [ -z "$is_managed" ]; then
		[ "$newStatus" = "Enabled" -a "$op" != "d" ] && services_reconf "$IPObject" "true" || services_reconf "$IPObject" "false"
	fi
}
restart_minissdpd() {
	local _obj=$1
	local _ip=""
	if [ -f /tmp/run/minissdpd.pid ]; then
		local _pid
		read _pid </tmp/run/minissdpd.pid
		[ -n "$_pid" ] && kill "$_pid"
	fi
	cmclient -v _ip GETV "$_obj.IPv4Address.1.IPAddress"
	[ -n $_ip ] && minissdpd -i "$_ip"
}
services_reconf() {
	local obj="$1" start="$2" is_upstream="" val="" objs="" nname=""
	case "$obj" in
	"Device.IP.Interface"*)
		cmclient -v is_upstream GETV "$obj.X_ADB_Upstream"
		p=""
		if [ -f /etc/ah/CustomReconf.sh ]; then
			. /etc/ah/CustomReconf.sh
			custom_reconf "$obj"
		fi
		cmclient -v interfaceType GETV ${obj}.X_ADB_ConnectionType
		if help_is_in_list "$interfaceType" "Management"; then
			if [ "$start" = "true" ]; then
				! help_ifmonitor_action_exist "$obj" "Up" "Device.ManagementServer.X_ADB_ConnectionRequestInterface" &&
					p="${p}Device.ManagementServer.X_ADB_ConnectionRequestInterface=${obj}	"
			else
				if ! help_ifmonitor_action_exist "$obj" "Down" "Device.ManagementServer.X_ADB_ConnectionRequestInterface"; then
					cmclient -v val GETV Device.ManagementServer.X_ADB_ConnectionRequestInterface
					if [ "$val" = "$obj" ]; then
						cmclient -v objs GETO "Device.IP.Interface.+.[X_ADB_ConnectionType>Management].[Status=Up]"
						i=""
						for i in $objs; do
							[ "$i" != "$obj" ] && break
						done
						[ -n "$i" ] && p="${p}Device.ManagementServer.X_ADB_ConnectionRequestInterface=${i}	"
					fi
				fi
			fi
			cmclient SETM "${p}" >/dev/null
			p=""
		fi
		local cp_enabled
		if [ "$is_upstream" = "true" ]; then
			cmclient -v cp_enabled GETV Device.CaptivePortal.Enable
			[ "$cp_enabled" = "true" ] &&
				cmclient -u boot SET "CaptivePortal.Enable" true ||
				cmclient -u boot SET "CaptivePortal.[X_ADB_ConnDownWarningEnable=true].X_ADB_ConnDownWarningEnable" true
		fi
		cmclient SET "Device.X_ADB_ParentalControl.[Enable=true].Reset" $(date) >/dev/null &
		[ "$is_upstream" = "false" ] && cmclient SET "Device.Services.X_ADB_RTSPProxy.[Enable=true].Enable" true
		if [ "$start" = "true" ]; then
			cmclient -v val GETV Device.X_ADB_DMZ.[Enable=true].UpstreamInterfaces
			if help_is_in_list "$val" "$obj"; then
				cmclient SET "Device.X_ADB_DMZ.Interface" "$obj" >/dev/null
			fi
			/etc/ah/DMZ.sh refresh
			/etc/ah/QoSClassification.sh refresh "$obj"
			if [ "$is_upstream" = "false" ]; then
				cmclient SET "Device.X_ADB_SSHServer.LocalAccess.[Enable=true].[Interfaces,${obj}].Enable" true
				cmclient SET "Device.X_ADB_SSHServer.LocalAccess.[Enable=true].[Interfaces=].Enable" true
				cmclient SET "Device.X_ADB_TelnetServer.LocalAccess.[Enable=true].[Interfaces,${obj}].Enable" true
				cmclient SET "Device.X_ADB_TelnetServer.LocalAccess.[Enable=true].[Interfaces=].Enable" true
				cmclient SET "Device.UserInterface.X_ADB_LocalAccess.[Enable=true].Reset" true
				cmclient SET "Device.Services.StorageService.1.FTPServer.[Enable=true].[X_ADB_Interfaces,${obj}].X_ADB_Refresh" true
				cmclient SET "Device.Services.StorageService.1.FTPServer.[Enable=true].[X_ADB_Interfaces=].X_ADB_Refresh" true
				cmclient SET "Device.Services.StorageService.1.HTTPServer.[Enable=true].X_ADB_Reset" true
				cmclient SET "Device.Services.StorageService.1.HTTPSServer.[Enable=true].X_ADB_Reset" true
			else
				cmclient SET "Device.X_ADB_SSHServer.RemoteAccess.[Enable=true].[Interfaces,${obj}].Enable" true
				cmclient SET "Device.X_ADB_SSHServer.RemoteAccess.[Enable=true].[Interfaces=].Enable" true
				cmclient SET "Device.X_ADB_TelnetServer.RemoteAccess.[Enable=true].[Interfaces,${obj}].Enable" true
				cmclient SET "Device.X_ADB_TelnetServer.RemoteAccess.[Enable=true].[Interfaces=].Enable" true
				cmclient SET "Device.Services.StorageService.1.X_ADB_FTPServerRemote.[Enable=true].[X_ADB_Interfaces,${obj}].X_ADB_Refresh" true
				cmclient SET "Device.Services.StorageService.1.X_ADB_FTPServerRemote.[Enable=true].[X_ADB_Interfaces=].X_ADB_Refresh" true
				cmclient -v val GETV UserInterface.RemoteAccess.Enable
				if [ "$val" = "true" ]; then
					cmclient SET "Device.UserInterface.RemoteAccess.X_ADB_Reset" true
				else
					cmclient SET "Device.UserInterface.X_ADB_LocalAccess.[Enable=true].Reset" true
				fi
				/etc/ah/NATPortMapping.sh refresh
				/etc/ah/NTP.sh refresh
			fi
			/etc/ah/TR069.sh IP_IF_CHANGED "$obj"
			[ -x /etc/ah/CWMP2.sh ] && /etc/ah/CWMP2.sh IP_IF_CHANGED "$obj"
			cmclient SET "Device.UPnP.Device.[Enable=true].[X_ADB_LanInterface=${obj}].Enable" true >/dev/null
		fi
		if [ "$is_upstream" = "true" ]; then
			[ -x /etc/ah/CustomWorkaround.sh ] && /etc/ah/CustomWorkaround.sh "del"
			help_lowlayer_ifname_get "nname" "$obj"
			if [ ${#nname} -ne 0 ]; then
				if [ "$changedOnlineStatus" = "1" -a "$newOnlineStatus" = "Up" ]; then
					help_iptables -t filter -A InputDeny.wan -p udp --destination-port 53 -j DROP -i $nname
					help_iptables -t filter -A InputDeny.wan -p tcp --destination-port 53 -j DROP -i $nname
					help_ip6tables -t filter -A InputDeny.wan -p udp --destination-port 53 -j DROP -i $nname
					help_ip6tables -t filter -A InputDeny.wan -p tcp --destination-port 53 -j DROP -i $nname
				elif [ "$changedOnlineStatus" = "1" -a "$newOnlineStatus" = "Down" ] || [ "$newOnlineStatus" = "Up" -a "$op" = "d" ]; then
					help_iptables -t filter -D InputDeny.wan -p udp --destination-port 53 -j DROP -i $nname
					help_iptables -t filter -D InputDeny.wan -p tcp --destination-port 53 -j DROP -i $nname
					help_ip6tables -t filter -D InputDeny.wan -p udp --destination-port 53 -j DROP -i $nname
					help_ip6tables -t filter -D InputDeny.wan -p tcp --destination-port 53 -j DROP -i $nname
				fi
			fi
			cmclient -v is_defaultroute GETV "$obj.X_ADB_DefaultRoute"
			[ -n "$obj" ] && cmclient SET "Device.Services.X_ADB_IGMPProxy.[Enable=true].[UpstreamInterfaces,$obj].Refresh" true
			if [ -f /etc/ah/DynamicDNS.sh ]; then
				cmclient SET "Device.Services.X_ADB_DynamicDNS.Client.[Enable=true].[Interface=${obj}].Enable" true
				[ "$is_defaultroute" = "true" ] &&
					cmclient SET "Device.Services.X_ADB_DynamicDNS.Client.[Enable=true].[Interface=].Enable" true
			fi
			if [ -f /etc/ah/L2TPClient.sh ]; then
				cmclient SET "Device.X_ADB_VPN.Client.L2TP.[Enable=true].[Interface=${obj}].Interface" "$obj"
			fi
			if [ -f /etc/ah/PPTPClient.sh ]; then
				cmclient SET "Device.X_ADB_VPN.Client.PPTP.[Enable=true].[Interface=${obj}].Interface" "$obj"
			fi
			if [ -f /etc/ah/PPTPServer.sh ]; then
				cmclient SET "Device.X_ADB_VPN.Server.PPTP.[Enable=true].[Interface=${obj}].Enable" true
				[ "$is_defaultroute" = "true" ] &&
					cmclient SET "Device.X_ADB_VPN.Server.PPTP.[Enable=true].[Interface=].Enable" true
			fi
			if [ -f /etc/ah/L2TPServer.sh ]; then
				cmclient SET "Device.X_ADB_VPN.Server.L2TP.[Enable=true].[Interface=${obj}].Enable" true
				[ "$is_defaultroute" = "true" ] &&
					cmclient SET "Device.X_ADB_VPN.Server.L2TP.[Enable=true].[Interface=].Enable" true
			fi
			if [ -f /etc/ah/IPv6rd.sh ]; then
				if [ "$start" = "true" ]; then
					cmclient -u "IPIfIPv4add" SET "Device.IPv6rd.[Enable=true].InterfaceSetting.[Enable=true].[AddressSource>$obj].Enable" true
				else
					cmclient -u "IPIfIPv4del" SET "Device.IPv6rd.[Enable=true].InterfaceSetting.[Enable=true].[AddressSource>$obj].Enable" true
				fi
			fi
			if [ -f /etc/ah/DHCPv6Client.sh -a "$start" = "false" ]; then
				cmclient DEL "Device.DHCPv6.Client.[Enable=true].[Interface=$obj].ReceivedOption"
				cmclient DEL "Device.DHCPv6.Client.[Enable=true].[Interface=$obj].Server"
			fi
			local _proxyEnable=""
			local _proxyObj="Device.Services.X_ADB_PPPoEProxy"
			cmclient -v _proxyEnable GETV "$_proxyObj.Enable"
			[ "$_proxyEnable" = "true" ] && cmclient SET "$_proxyObj.Reset" true
			if [ -e /etc/ah/helper_ipsec.sh ]; then
				if [ "$is_defaultroute" = "true" ]; then
					cmclient SET "Device.IPsec.X_ADB_Reset" "true"
				else
					local isIPsecIP IPsecLocEndp
					cmclient -v IPsecLocEndp GETV IPsec.Profile.X_ADB_LocalEndpoint
					for i in $IPsecLocEndp; do
						if [ "$obj" = "$i" ]; then
							cmclient SET "Device.IPsec.X_ADB_Reset" "true"
							break
						fi
					done
				fi
			fi
			if [ -f /etc/ah/Stun.sh ]; then
				cmclient -v val GETV Device.ManagementServer.X_ADB_ConnectionRequestInterface
				if [ "$val" = "$obj" ]; then
					if [ "$start" = "true" ]; then
						cmclient SET "Device.ManagementServer.[STUNEnable=true].STUNEnable" true
					else
						cmclient -v stunStatus GETV Device.ManagementServer.STUNEnable
						[ "$stunStatus" = "true" ] && /etc/ah/Stun.sh stop
					fi
				fi
			fi
		else
			cmclient -v neighitf GETO Device.NeighborDiscovery.InterfaceSetting.[Interface=$obj]
			for neigh in $neighitf; do
				cmclient SET "$neigh.Status" "Enabled"
			done
		fi
		cmclient SET "Device.Services.StorageService.1.X_ADB_HTTPServerRemote.[Enable=true].X_ADB_Reset" true
		cmclient SET "Device.Services.StorageService.1.X_ADB_HTTPSServerRemote.[Enable=true].X_ADB_Reset" true
		cmclient -v cupsEnable GETV "Device.Services.X_ADB_PrinterService.Enable"
		if [ "$cupsEnable" = "true" ]; then
			cmclient -v cupsInterfaces GETV "Device.Services.X_ADB_PrinterService.Interfaces"
			if [ -z "$cupsInterfaces" ]; then
				cmclient SET "Device.Services.X_ADB_PrinterService.Interfaces" ""
			fi
		fi
		if [ -d "/tmp/ipsec" ]; then
			local ipsec_filter
			cmclient -v ipsec_filter GETO "Device.IPsec.Filter.*.[Interface=${obj}].[Enable=true]"
			[ -n "$ipsec_filter" ] && cmclient SET "Device.IPsec.X_ADB_Reset" "true"
		fi
		;;
	esac
	return 0
}
service_config() {
	if [ "$changedOnlineStatus" -eq 1 -o "$op" = "d" ]; then
		cmclient -v monObj GETV "$obj.MonitoredInterface"
		if [ "$newOnlineStatus" = "Up" -a "$op" != "d" ]; then
			services_reconf "$monObj" "true" &
		elif [ "$newOnlineStatus" = "Down" ] || [ "$newOnlineStatus" = "Up" -a "$op" = "d" ]; then
			services_reconf "$monObj" "false" &
		fi
	fi
}
if [ $# -eq 3 ] && [ "$1" = "ipifdel" ]; then
	obj="$2"
	upstream="$3"
	if [ "$upstream" = "true" ]; then
		help_object_remove_references "Device.UserInterface.RemoteAccess.X_ADB_Interface" "$obj"
		help_object_remove_references "Device.X_ADB_SSHServer.RemoteAccess.Interfaces" "$obj"
		help_object_remove_references "Device.X_ADB_TelnetServer.RemoteAccess.Interface" "$obj"
	else
		help_object_remove_references "Device.UserInterface.X_ADB_LocalAccess.Interface" "$obj"
		help_object_remove_references "Device.X_ADB_SSHServer.LocalAccess.Interfaces" "$obj"
		help_object_remove_references "Device.X_ADB_TelnetServer.LocalAccess.Interface" "$obj"
		help_object_remove_references "Device.Services.X_ADB_PrinterService.Interfaces" "$obj"
	fi
	exit 0
fi
case "$obj" in
"Device.IP.Interface."*".IPv"[46]"Address"*)
	case "$op" in
	d)
		IPServices
		;;
	s)
		if [ "$newStatus" != "Error_Misconfigured" ]; then
			if help_post_provisioning_add "$obj.Status" "$newStatus" "High"; then
				command -v renice >/dev/null && renice -n15 $$
				IPServices &
			fi
		fi
		;;
	esac
	;;
"Device.X_ADB_InterfaceMonitor"*)
	case "$op" in
	s | d)
		service_config
		;;
	esac
	;;
esac
exit 0
