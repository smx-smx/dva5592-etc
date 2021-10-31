#!/bin/sh
#udp:async-pack,ppp,*
#sync:max=3
. /etc/ah/helper_serialize.sh && help_serialize "${LINKNAME}" >/dev/null
. /etc/ah/helper_functions.sh
EH_NAME="PPPAsyncPack"
ip_obj=""
updateRoutingRouter() {
	local ip_router
	cmclient -v ip_router GETV "$ip_obj.Router"
	if [ -z "$ip_router" ]; then
		echo "### $EH_NAME: ADD <Device.Routing.Router>" >>/dev/console
		cmclient -v router_index ADD "Device.Routing.Router"
		ip_router="Device.Routing.Router.${router_index}"
		cmclient SET "$ip_router.Enable" "true"
		cmclient SET "$ip_obj.Router" "$ip_router"
	fi
	local i=1
	eval route=\$PPP_IP_ROUTE_ADD$i
	while [ "$route" != "" ]; do
		set -f
		[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
		IFS=";"
		set -- $route
		[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
		set +f
		cmclient -v iproute_index ADD "$ip_router.IPv4Forwarding"
		ip_route="$ip_router.IPv4Forwarding.$iproute_index"
		echo "### $EH_NAME: ADD <$ip_route>" >>/dev/console
		echo "### $EH_NAME: SET <$ip_route.GatewayIPAddress> <$3>" >>/dev/console
		echo "### $EH_NAME: SET <$ip_route.Interface> <$ip_obj>" >>/dev/console
		echo "### $EH_NAME: SET <$ip_route.StaticRoute> <false>" >>/dev/console
		echo "### $EH_NAME: SET <$ip_route.ForwardingMetric> <$4>" >>/dev/console
		setm_params="$ip_route.GatewayIPAddress=$3"
		setm_params="$setm_params	$ip_route.Interface=$ip_obj"
		setm_params="$setm_params	$ip_route.StaticRoute=false"
		setm_params="$setm_params	$ip_route.ForwardingMetric=$4"
		if [ "$1" = "0.0.0.0" ] && [ "$2" = "0.0.0.0" ]; then
			echo "### $EH_NAME: SET Route As Default" >>/dev/console
		else
			echo "### $EH_NAME: SET <$ip_route.DestIPAddress> <$1>" >>/dev/console
			echo "### $EH_NAME: SET <$ip_route.DestSubnetMask> <$2>" >>/dev/console
			setm_params="$setm_params	$ip_route.DestIPAddress=$1"
			setm_params="$setm_params	$ip_route.DestSubnetMask=$2"
		fi
		echo "### $EH_NAME: SET <$ip_route.Enable> <true>" >>/dev/console
		setm_params="$setm_params	$ip_route.Enable=true"
		cmclient SETM "$setm_params" >/dev/null
		i=$((i + 1))
		eval route=\$PPP_IP_ROUTE_ADD$i
	done
}
eventHandler_pppAsyncPack() {
	cmclient -v ip_obj GETO "Device.IP.Interface.[LowerLayers,$LINKNAME]"
	updateRoutingRouter
	local ppp_url_disc
	cmclient -v ppp_url_disc GETV Device.ManagementServer.X_ADB_EnablePPPURLDiscovery
	if [ "$ppp_url_disc" = "true" -a "${#PPP_HURL}" -gt 0 ]; then
		local url
		local acsurl="$PPP_HURL"
		cmclient -v url GETV Device.ManagementServer.URL
		if [ "$url" != "$acsurl" ]; then
			echo "### $EH_NAME: SET <Device.ManagementServer.URL> <$acsurl>" >>/dev/console
			cmclient -u "${EH_NAME}" SET Device.ManagementServer.URL "$acsurl"
		fi
	fi
	local i=1
	local ppp_ntp_disc
	cmclient -v ppp_ntp_disc GETV Device.Time.X_ADB_EnablePPPNTPServerDiscovery
	if [ "$ppp_ntp_disc" = "true" ]; then
		eval ntp=\$PPP_MOTM$i
		while [ "$ntp" != "" -a $i -lt 6 ]; do
			cmclient -v actntp GETV "Device.Time.NTPServer$i"
			if [ "$ntp" != "$actntp" ]; then
				echo "### $EH_NAME: SET <Device.Time.NTPServer$i> <$ntp>" >>/dev/console
				cmclient SET "Device.Time.NTPServer$i" "$ntp"
			fi
			i=$((i + 1))
			eval ntp=\$PPP_MOTM$i
		done
		while [ $i -gt 1 -a $i -lt 6 ]; do
			cmclient -v actntp GETV "Device.Time.NTPServer$i"
			if [ ${#actntp} -ne 0 ]; then
				echo "### $EH_NAME: SET <Device.Time.NTPServer$i> <>" >>/dev/console
				cmclient SET "Device.Time.NTPServer$i" ""
			fi
			i=$((i + 1))
		done
	fi
}
eventHandler_pppAsyncPack
