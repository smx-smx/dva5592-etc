#!/bin/sh
AH_NAME="VoIPURI"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
. /etc/ah/helper_serialize.sh && help_serialize >/dev/null
case "$op" in
s)
	cmclient SETE "$obj.X_ADB_URI" "$newURI"
	;;
g)
	uri=$(cmclient GETV -u ${AH_NAME} "$obj.X_ADB_URI")
	case $uri in
	"sip:"*"@"*)
		printf "%s\n" "$uri"
		return 0
		;;
	esac
	obj_profile="${obj%%.Line.*}"
	obj_line="${obj%%.SIP}"
	proxy=$(cmclient GETV -u ${AH_NAME} "${obj_profile}.SIP.ProxyServer")
	domain=$(cmclient GETV -u ${AH_NAME} "${obj_profile}.SIP.UserAgentDomain")
	dirn=$(cmclient GETV -u ${AH_NAME} "${obj_line}.DirectoryNumber")
	if [ "$uri" = "sip:" ]; then
		uri=""
	fi
	case $uri in
	"sip:"*)
		prefix="${uri}@"
		;;
	*)
		prefix="sip:${dirn}@"
		;;
	esac
	if [ ${#domain} -eq 0 ]; then
		printf "%s\n" "${prefix}${proxy}"
	else
		printf "%s\n" "${prefix}${domain}"
	fi
	;;
esac
exit 0
