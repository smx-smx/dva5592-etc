#!/bin/sh
AH_NAME="DynamicDNS"
pid_file="/tmp/${AH_NAME}${obj}.pid"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ -f /tmp/upgrading.lock ] && [ "$op" != "g" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
. /etc/ah/helper_functions.sh
. /etc/ah/helper_svc.sh
clientID=${obj#*X_ADB_DynamicDNS.}
service_config() {
	help_svc_start "ddns_client.sh $obj" "ddns_client_${clientID}" '' '' '' '' $pid_file
}
kill_delayed() {
	help_svc_stop "ddns_client_${clientID}" $pid_file 15
}
case "$op" in
s)
	help_is_changed Interface Provider Hostname Username Password Offline IPv6Support && setEnable=1
	if [ "$newEnable" = true -a "$setEnable" = 1 ]; then
		kill_delayed
		cmclient SETE "$obj".Status Registering
		service_config
	elif [ "$changedEnable" = 1 ]; then
		kill_delayed
		cmclient SETE "$obj".Status Disabled
		cmclient -v provider_name GETV "$newProvider".Name
		logger -t "cm" -p 6 "DynDNS: deactivated ${newHostname} on ${provider_name}"
	fi
	;;
d)
	kill_delayed
	cmclient -v provider_name GETV "$newProvider".Name
	logger -t "cm" -p 6 "DynDNS: removed ${newHostname} on ${provider_name}"
	;;
esac
exit 0
