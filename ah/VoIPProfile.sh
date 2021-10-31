#!/bin/sh
[ "$user" = "stats" ] && exit 0
. /etc/ah/VoIPCommon.sh
AH_NAME="VoIPProfile"
serviceId="${obj##*.VoiceService.}"
serviceId="${serviceId%%.*}"
VOIP_SERVICE="Services.VoiceService.${serviceId}"
VOIP_PROFILE="${VOIP_SERVICE}.VoiceProfile"
MAXexpBackoffTimerB=10
if [ "$op" = "r" ]; then
	profileId="$1"
else
	profileId="${obj##*.VoiceProfile.}"
	profileId="${profileId%%.*}"
fi
profobj=""
profobj="${obj#*VoiceProfile.}"
subprofobj="${profobj#*.}"
if [ "$profobj" = "$subprofobj" ]; then
	profobj="VoiceProfile"
else
	profobj="${subprofobj%%.*}"
fi
case "$profobj" in
"VoiceProfile") ;;

"SIP")
	sipObj="${obj##*${VOICE_PROFILE}.${profileId}.SIP.}"
	sipObj="${sipObj%%.*}"
	case "$sipObj" in
	"EventSubscribe")
		profobj="SIP.EventSubscribe"
		;;
	*) ;;

	esac
	;;
*) ;;

esac
numplan_populate() {
	local capnum FacilityValue profileobj prefix prefixw prefixInfo setm n
	profileobj="$1"
	cmclient -v capnum GETV Device.Services.VoiceService.1.Capabilities.NumberingPlan
	[ "$capnum" = "false" ] && return 0
	cmclient -v prefixInfo GETO ${VOIP_SERVICE}.X_ADB_NumberingPlan.PrefixInfo
	for prefix in $prefixInfo; do
		setm=""
		cmclient -v n ADD ${profileobj}.NumberingPlan.PrefixInfo
		prefixw="${profileobj}.NumberingPlan.PrefixInfo.${n}"
		cmclient -v FacilityValue GETV ${prefix}.FacilityAction
		setm="${prefixw}.FacilityAction=${FacilityValue}"
		cmclient -v FacilityValue GETV ${prefix}.FacilityActionArgument
		setm="$setm	${prefixw}.FacilityActionArgument=${FacilityValue}"
		cmclient -v FacilityValue GETV ${prefix}.NumberOfDigitsToRemove
		setm="$setm	${prefixw}.NumberOfDigitsToRemove=${FacilityValue}"
		cmclient -v FacilityValue GETV ${prefix}.PosOfDigitsToRemove
		setm="$setm	${prefixw}.PosOfDigitsToRemove=${FacilityValue}"
		cmclient -v FacilityValue GETV ${prefix}.PrefixMaxNumberOfDigits
		setm="$setm	${prefixw}.PrefixMaxNumberOfDigits=${FacilityValue}"
		cmclient -v FacilityValue GETV ${prefix}.PrefixMinNumberOfDigits
		setm="$setm	${prefixw}.PrefixMinNumberOfDigits=${FacilityValue}"
		cmclient -v FacilityValue GETV ${prefix}.PrefixRange
		setm="$setm	${prefixw}.PrefixRange=${FacilityValue}"
		cmclient -v FacilityValue GETV ${prefix}.X_ADB_DigitManipulation.StripDigits
		setm="$setm	${prefixw}.X_ADB_DigitManipulation.StripDigits=${FacilityValue}"
		cmclient -v FacilityValue GETV ${prefix}.X_ADB_DigitManipulation.AddPrefix
		setm="$setm	${prefixw}.X_ADB_DigitManipulation.AddPrefix=${FacilityValue}"
		cmclient SETM "${setm}"
	done
}
service_add() {
	local numOfProfiles
	local maxProfiles
	local profiles
	case "$profobj" in
	SIP.EventSubscribe)
		cmclient -v lobjs GETO "${VOIP_PROFILE}.${profileId}.Line"
		for line in $lobjs; do
			cmclient -u voip ADD $line.SIP.EventSubscribe.
		done
		;;
	VoiceProfile)
		cmclient -v profiles GETO ${VOIP_SERVICE}.VoiceProfile
		set -- $profiles
		numOfProfiles=$#
		cmclient -v maxProfiles GETV ${VOIP_SERVICE}.Capabilities.MaxProfileCount
		[ -n $maxProfiles ] && [ $numOfProfiles -gt $maxProfiles ] && cmclient DEL $obj && return 4
		cmclient ADD $obj.Line
		numplan_populate ${obj}
		;;
	esac
	service_reload
	return 0
}
service_delete() {
	case "$profobj" in
	SIP.EventSubscribe)
		sipId="${obj##*SIP.EventSubscribe.}"
		local lobjs
		cmclient -v lobjs GETO "${VOIP_PROFILE}.${profileId}.Line"
		for line in $lobjs; do
			cmclient -u voip DEL $line.SIP.EventSubscribe.$sipId
		done
		;;
	esac
	service_reload
	reconf_voip_iptables
}
config_sip_timer() {
	local changedvalue="" timervalue=0
	case "$profobj" in
	"SIP")
		changedvalue="$changedTimerT1"
		if [ "$changedvalue" = 1 ]; then
			timervalue="$((newTimerT1 * 64))"
			cmclient -u "$user" SETE "${VOIP_PROFILE}.${profileId}.SIP.TimerB" $timervalue
		else
			changedvalue="$changedTimerB"
			if [ "$changedvalue" = 1 ]; then
				cmclient -v timert1 GETV "${VOIP_PROFILE}.${profileId}.SIP.TimerT1"
				if [ "$timert1" != "" ]; then
					local resultime=0
					local nextresultime=0
					resultime="$timert1"
					local cnt=1
					while [ $cnt -lt $MAXexpBackoffTimerB ]; do
						resultime="$((2 * resultime))"
						nextresultime="$((2 * resultime))"
						if [ $resultime -eq $newTimerB ] || [ $newTimerB -gt $resultime -a $newTimerB -lt $nextresultime ]; then
							cmclient -u "$user" SETE "${VOIP_PROFILE}.${profileId}.SIP.TimerB" $resultime
							break
						fi
						cnt=$((cnt + 1))
					done
					[ $cnt -eq $MAXexpBackoffTimerB ] && timer_set=1
				else
					timer_set=1
				fi
			fi
		fi
		;;
	esac
}
config_special_case() {
	case "$profobj" in
	"FaxT38")
		if [ "$changedX_ADB_UDPTLLocalPortMin" = "1" -o "$changedX_ADB_UDPTLLocalPortMax" = "1" ]; then
			init_natskip "FaxT38" "$newX_ADB_UDPTLLocalPortMin" "$newX_ADB_UDPTLLocalPortMax"
		fi
		;;
	"RTP")
		if [ "$changedLocalPortMin" = "1" -o "$changedLocalPortMax" = "1" ]; then
			init_natskip "RTP" "$newLocalPortMin" "$newLocalPortMax"
			if [ -x /etc/ah/RestrictedHost.sh ]; then
				/etc/ah/RestrictedHost.sh enable
			fi
		fi
		;;
	"SIP.EventSubscribe")
		if [ "$changedEvent" = "1" ]; then
			local eobjs
			cmclient -v eobjs GETO "${VOIP_PROFILE}.${profileId}.Line.*.SIP.EventSubscribe.*.[Event="$oldEvent"]"
			for line in $eobjs; do
				cmclient -u voip SET ${line}.Event "$newEvent"
			done
		fi
		;;
	esac
}
check_allow_config() {
	if [ "$changedLocalPortMin" = "1" -o "$changedLocalPortMax" = "1" ]; then
		if [ $newLocalPortMin -gt $newLocalPortMax ]; then
			deny_set="1"
		fi
	fi
	if [ "$changedX_ADB_UDPTLLocalPortMin" = "1" -o "$changedX_ADB_UDPTLLocalPortMax" = "1" ]; then
		if [ $newX_ADB_UDPTLLocalPortMin -gt $newX_ADB_UDPTLLocalPortMax ]; then
			deny_set="1"
		fi
	fi
	if [ "$changedNotifierTransport" = "1" ]; then
		deny_set="1"
		if [ "$newNotifierTransport" != "" ]; then
			cmclient -v transport GETV ${VOIP_SERVICE}.Capabilities.SIP.Transports
			case "$transport" in
			*$newNotifierTransport*)
				cmclient -v proxyservertransport GETV ${VOIP_PROFILE}.${profileId}.SIP.ProxyServerTransport
				if [ "$proxyservertransport" = "$newNotifierTransport" ]; then
					deny_set=0
				else
					deny_set=1
				fi
				;;
			esac
		fi
	fi
	if [ "$changedProxyServerTransport" = "1" ]; then
		deny_set="1"
		if [ "$newProxyServerTransport" != "" ]; then
			cmclient -v transport GETV ${VOIP_SERVICE}.Capabilities.SIP.Transports
			case "$transport" in
			*$newProxyServerTransport*)
				cmclient SET ${VOIP_PROFILE}.${profileId}.SIP.RegistrarServerTransport $newProxyServerTransport &
				cmclient SET ${VOIP_PROFILE}.${profileId}.SIP.UserAgentTransport $newProxyServerTransport &
				local eobjs
				cmclient -v eobjs GETO "${VOIP_PROFILE}.${profileId}.SIP.EventSubscribe"
				for eventsubiscribe in $eobjs; do
					cmclient SET $eventsubiscribe.NotifierTransport $newProxyServerTransport &
				done
				deny_set=0
				;;
			esac
		fi
	fi
	if [ "$changedRegistrarServerTransport" = "1" ]; then
		deny_set="1"
		if [ "$newRegistrarServerTransport" != "" ]; then
			cmclient -v transport GETV ${VOIP_SERVICE}.Capabilities.SIP.Transports
			case "$transport" in
			*$newRegistrarServerTransport*)
				cmclient -v proxyservertransport GETV ${VOIP_PROFILE}.${profileId}.SIP.ProxyServerTransport
				if [ "$proxyservertransport" = "$newRegistrarServerTransport" ]; then
					deny_set=0
				else
					deny_set=1
				fi
				;;
			esac
		fi
	fi
	if [ "$changedUserAgentTransport" = "1" ]; then
		deny_set="1"
		if [ "$newUserAgentTransport" != "" ]; then
			cmclient -v transport GETV ${VOIP_SERVICE}.Capabilities.SIP.Transports
			case "$transport" in
			*$newUserAgentTransport*)
				cmclient -v proxyservertransport GETV ${VOIP_PROFILE}.${profileId}.SIP.ProxyServerTransport
				if [ "$proxyservertransport" = "$newUserAgentTransport" ]; then
					deny_set=0
				else
					deny_set=1
				fi
				;;
			esac
		fi
	fi
}
service_config() {
	deny_set="0"
	check_allow_config
	if [ "$deny_set" = "1" ]; then
		return 2
	fi
	config_special_case
	timer_set="0"
	config_sip_timer
	if [ "$timer_set" = "1" ]; then
		return 2
	fi
	service_reload
	[ "$changedEnable" = "1" ] && reconf_voip_iptables
	return 0
}
ret=0
case "$op" in
a)
	service_add
	ret=$?
	;;
d)
	service_delete
	;;
s)
	service_config
	ret=$?
	;;
esac
exit $ret
