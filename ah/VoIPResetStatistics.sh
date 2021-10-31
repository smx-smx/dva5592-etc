#!/bin/sh
[ "$user" = "voip" ] && exit 0
AH_NAME="VoIPResetStatistics"
VOIP_CTRLIF_ADDR="local:/tmp/voip_socket"
phyId="${obj##*.PhyInterface.}"
phyId="${phyId%%.*}"
service_config() {
	local srv prf line
	if [ "$changedResetStatistics" = "1" -a "$newResetStatistics" = "true" ]; then
		if pidof voip; then
			phyStats="${obj##*.}"
			if [ "$phyStats" = "X_TELECOMITALIA_IT_Stats" ]; then
				echo PHYRESETSTATS $phyId | nc $VOIP_CTRLIF_ADDR
			else
				srv="${obj##*.VoiceService.}"
				srv="${srv%%.*}"
				prf="${obj##*.VoiceProfile.}"
				prf="${prf%%.*}"
				line="${obj##*.Line.}"
				line="${line%%.*}"
				echo LINERESETSTATS $srv $prf $line | nc $VOIP_CTRLIF_ADDR
			fi
		fi
		cmclient -u voip SET "$obj.ResetStatistics" "false"
	fi
	return 0
}
ret=0
case "$op" in
s)
	service_config
	ret=$?
	;;
esac
exit $ret
