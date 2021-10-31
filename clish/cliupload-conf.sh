#!/bin/sh
. /etc/clish/clish-commons.sh
fwRule=""
fwEnabled=""
port_arg=""
check_tftp_fw_rule() {
	local fwLevel startPort endPort
	cmclient -v fwLevel GETV "Device.Firewall.[Enable=true].[Config=Advanced].AdvancedLevel"
	[ -z "$fwLevel" ] && return
	cmclient -v fwChain GETV "${fwLevel}.Chain"
	[ -z "$fwChain" ] && return
	cmclient -v fwRule GETO "$fwChain.Rule.[Alias=TFTP].[DestInterface=X_ADB_Local]"
	[ -z "$fwRule" ] && return
	cmclient -v fwEnabled GETV "${fwRule}.Enable"
	[ "${fwEnabled}" = "false" ] && cmclient SET "${fwRule}.Enable" true >/dev/null
	cmclient -v startPort GETV "${fwRule}.DestPort"
	cmclient -v endPort GETV "${fwRule}.DestPortRangeMax"
	port_arg="-p ${startPort}:${endPort}"
}
ctype=$1
proto=$2
url_addr=$3
[ ${#url_addr} -eq 0 ] && die "ERROR: Undefined url address"
if [ "$proto" = "http" ]; then
	case "$url_addr" in
	https*) proto="https" ;;
	esac
fi
case "$proto" in
https)
	[ "$4" = "true" ] && cert_opt="-C"
	if [ -z "$5" -o -z "$6" ]; then
		url=$url_addr
	else
		url="https://$5:$6@${url_addr#https://}"
	fi
	;;
http)
	if [ -z "$5" -o -z "$6" ]; then
		url="http://${url_addr#http://}"
	else
		url="http://$5:$6@${url_addr#http://}"
	fi
	;;
tftp)
	url="tftp://${url_addr#tftp://}"
	check_tftp_fw_rule
	;;
ftp)
	[ -z "$4" -o -z "$5" ] && die "ERROR: Undefined login/password"
	url="ftp://$4:$5@${url_addr#ftp://}"
	;;
*)
	die "ERROR: Unsupported upload method: $proto"
	;;
esac
fname="data_$(date +%Y%m%d_%H%M).bin"
fifoname="/tmp/upgrade/cfg-backup_CLI_${ctype}"
rm -f "$fifoname" >/dev/null 2>&1
mknod "$fifoname" p
echo "Start uploading ${fname}..."
if yaft -t 15 $cert_opt -u "${url}/${fname}" -f "$fifoname" $port_arg; then
	echo "Upload OK"
else
	echo "Upload FAIL"
fi
[ -n "${fwRule}" -a -n "${fwEnabled}" ] && cmclient SET "${fwRule}.Enable" "${fwEnabled}" >/dev/null
rm -f "$fifoname" >/dev/null 2>&1
exit 0
