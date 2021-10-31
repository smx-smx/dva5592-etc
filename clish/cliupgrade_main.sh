#!/bin/sh
. /etc/clish/clish-commons.sh
[ -f /etc/ah/helper_customer_common.sh ] && . /etc/ah/helper_customer_common.sh
trap "" HUP # Avoid certain death when issued from telnet or SSH
doNotCertCheck="false"
transfer_custom_opts=""
log() {
	echo "$@" >/dev/console
	echo "$@" >&2
}
fwRule=""
fwEnabled=""
port_arg=""
fsupgrade=0
check_tftp_fw_rule() {
	local fwLevel startPort endPort
	cmclient -v fwLevel GETV "Device.Firewall.[Enable=true].[Config=Advanced].AdvancedLevel"
	[ -z "$fwLevel" ] && return
	cmclient -v fwChain GETV "${fwLevel}.Chain"
	[ -z "$fwChain" ] && return
	cmclient -v fwRule GETO "${fwChain}.Rule.[Alias=TFTP].[DestInterface=X_ADB_Local]"
	[ -z "$fwRule" ] && return
	cmclient -v fwEnabled GETV "${fwRule}.Enable"
	[ "${fwEnabled}" = "false" ] && cmclient SET "${fwRule}.Enable" true >/dev/null
	cmclient -v startPort GETV "${fwRule}.DestPort"
	cmclient -v endPort GETV "${fwRule}.DestPortRangeMax"
	echo "-p ${startPort}:${endPort}"
}
firmware_validation() {
	local check_result=$(/usr/sbin/upgrade-check-url.sh "$url" "$doNotCertCheck")
	check_result="${check_result##*check_result||}"
	case "$check_result" in
	"new")
		log "Upgrade In Progress ($check_result firmware)"
		return 0
		;;
	"old" | "same")
		log "ERROR: firmware is $check_result!"
		;;
	*not_valid_image_file*)
		log "ERROR: firmware is invalid!"
		;;
	*file_not_loaded*)
		log "ERROR: firmware is unreachable!"
		;;
	*)
		log "ERROR: firmware is invalid or unreachable!"
		;;
	esac
	return 1
}
prepare_upgrade() {
	local timeout=0 prepare_file="/tmp/upgrade/upgrade-prepare"
	[ $fsupgrade -eq 1 ] && prepare_file="${prepare_file}-usb"
	: >>$prepare_file
	while [ -e "$prepare_file" -a $timeout -lt 20 ]; do
		sleep 1
		timeout=$(($timeout + 1))
	done
	[ -f /etc/ah/helper_customer_common.sh ] && help_custom_settings transfer_custom_opts
}
do_transfer() {
	local downloaded_fname="$1" custom_opts="$2"
	local result
	case "$url" in
	"file://"*)
		cp "${url#file://}" "$downloaded_fname"
		result=$?
		[ $result -ne 0 ] && log "ERROR: upgrading from \"${url}\" failed!"
		;;
	*)
		/bin/yaft -t 15 $cert_opt -d "$url" -o "$downloaded_fname" $port_arg "$custom_opts"
		result=$?
		[ $result -ne 0 ] && log "ERROR: downloading from \"${url}\" failed!" || log "Downloading from \"${url}\" completed."
		;;
	esac
	[ -n "${fwRule}" -a -n "${fwEnabled}" ] && cmclient SET "${fwRule}.Enable" "${fwEnabled}" >/dev/null
	return $result
}
proto=$2
[ ${#3} -eq 0 ] && die "ERROR: Undefined url address"
if [ "$proto" = "http" ]; then
	case "$3" in
	https*) proto="https" ;;
	http*) proto="http" ;;
	tftp*) proto="tftp" ;;
	ftp*) proto="ftp" ;;
	esac
fi
case "$proto" in
https)
	if [ "$4" = "true" ]; then
		doNotCertCheck="true"
		cert_opt="-C"
	fi
	if [ -z "$5" -o -z "$6" ]; then
		url=$3
	else
		url="https://$5:$6@${3#https://}"
	fi
	;;
http)
	if [ -z "$5" -o -z "$6" ]; then
		url="http://${3#http://}"
	else
		url="http://$5:$6@${3#http://}"
	fi
	;;
tftp)
	url="tftp://${3#tftp://}"
	port_arg="$(check_tftp_fw_rule)"
	;;
ftp)
	[ -z "$4" -o -z "$5" ] && die "ERROR: Undefined login/password"
	url="ftp://$4:$5@${3#ftp://}"
	;;
fs)
	rpath="${3#file://}"
	apath=$(cd -P "$(dirname "$rpath")" 2>/dev/null && pwd -P)
	case "$apath" in
	"/mnt/sd"*)
		url="file://$rpath"
		;;
	*)
		die "ERROR: Unsupported file path: $3"
		;;
	esac
	fsupgrade=1
	;;
*)
	die "ERROR: Unsupported upgrade method: $proto"
	;;
esac
case "$1" in
config)
	fconf="/tmp/upgrade/cfg-restore"
	log "Downloading configuration ..."
	do_transfer "/tmp/conf.xml" "$transfer_custom_opts" || exit 1
	log "Upgrading configuration ..."
	mv "/tmp/conf.xml" "$fconf" && cat /dev/null >>"$fconf"
	while [ -e "$fconf" ]; do
		sleep 1
	done
	[ -f /tmp/upgrade.log ] && grep -v "/usr/sbin/upgrade" /tmp/upgrade.log
	;;
firmware)
	firmware_validation || die
	log "Preparing upgrade"
	prepare_upgrade
	log "Downloading new firmware ..."
	if ! do_transfer "/tmp/fw.bin" "$transfer_custom_opts"; then
		cmclient REBOOT >/dev/null
		exit 1
	fi
	log "Prepare writing ..."
	mv /tmp/fw.bin /tmp/upgrade/fw.bin && cat /dev/null >>/tmp/upgrade/fw.bin
	[ -f /etc/ah/helper_customer_common.sh ] && help_custom_print_upgrade_log
	;;
esac
