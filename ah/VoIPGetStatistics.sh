#!/bin/sh
AH_NAME="VoIPGetStatistic"
VOIP_CTRLIF_ADDR="local:/tmp/voip_socket"
service_get() {
	local param=$1
	local str
	[ "$user" = voip ] && printf "0\n" && return
	if [ "$param" = "SessionDuration" ]; then
		str=$(cmclient GETV "$obj".SessionStartTime)
		str="${str%?}"
		str="${str%T*} ${str#*T}"
		str=$(($(date -u +%s) - $(date -u --date="$str" +%s)))
	else
		str=$(echo "GET $profileId $vlineId $param" | nc $VOIP_CTRLIF_ADDR 2>/dev/null)
	fi
	[ "$str" != "ERR" ] && printf "%s\n" "$str"
}
profileId="${obj##*.VoiceProfile.}"
profileId="${profileId%%.*}"
vlineId="${obj##*.Line.}"
vlineId="${vlineId%%.*}"
ret=0
case "$op" in
g)
	for arg; do # Arg list as separate words
		service_get "$arg"
	done
	exit 0
	;;
esac
exit $ret
