#!/bin/sh
. /etc/ah/target.sh
[ ! -x /bin/ledctl ] && exit 0
if [ "$user" = "boot" ] && [ "$newEnable" = "true" ]; then
	user="" obj="" /etc/ah/Led.sh
	exit 0
fi
evaluateCondition() {
	[ "$op" = "d" -a "$parameterOp" = "Empty" -a "$obj" = "${parameterPath%.*}" ] && return 1
	[ "$op" = "d" -a "$parameterOp" = "NotEmpty" -a "$obj" = "${parameterPath%.*}" ] && return 0
	case ${1} in
	"Equal") [ "${2}" = "${3}" ] && return 1 || return 0 ;;
	"NotEqual") [ "${2}" != "${3}" ] && return 1 || return 0 ;;
	"Contain")
		case ${2} in *"${3}"*) return 1 ;; esac
		return 0
		;;
	"NotContain")
		case ${2} in *"${3}"*) return 0 ;; esac
		return 1
		;;
	"Empty" | "ObjNotPresent") [ -z "${2}" ] && return 1 || return 0 ;;
	"NotEmpty" | "ObjPresent") [ -z "${2}" ] && return 0 || return 1 ;;
	"Greater" | "CountObj_>") [ "${2}" -gt "${3}" ] && return 1 || return 0 ;;
	"Less") [ "${2}" -lt "${3}" ] && return 0 || return 1 ;;
	esac
}
setLED() {
	cmd="ledctl -s -n ${name} -c ${colour} -u ${dutyCycle}"
	if [ "$dutyCycle" = "blinkingOnActivity" -o "$LEDStatus" = "blinkingFastOnActivity" -o "$LEDStatus" = "blinkingSlowOnActivity" ]; then
		cmd="${cmd} -b -e -r ${activityReference}"
	else
		cmd="${cmd} -b -d"
	fi
	$cmd
}
countObj() {
	local list=$1 entry count=0
	for entry in $list; do
		[ "$op" = "d" -a "$obj" = "$entry" ] || count=$((count + 1))
	done
	return $count
}
if [ "$op" = "g" ]; then
	ledname=""
	for arg; do
		case "$arg" in
		CurrentDutyCycle)
			cmclient -v ledname GETV $obj.Name
			ledctl -g -n "$ledname" --gstatus
			;;
		esac
	done
	exit 0
fi
case "$obj" in
Device.USB.USBHosts.Host.?.Device.*)
	cmclient -v LEDs GETO "Device.X_ADB_LED.ServiceLED.[Enable=true].+.[Name>USB]"
	;;
"Device.Services.VoiceService."*)
	if [ "${obj#*DECT}" = $obj ]; then
		cmclient -v LEDs GETO "Device.X_ADB_LED.ServiceLED.[Enable=true].+.[Name>LINE]"
	fi
	;;
esac
if [ ${#LEDs} -eq 0 ]; then
	if [ -n "$obj" ]; then
		cmclient -v LEDs GETO "Device.X_ADB_LED.ServiceLED.[Enable=true].+.[Behaviour.Trigger.Parameter>${obj}]"
		if [ ${#LEDs} -eq 0 ]; then
			cmclient -v countobjs GETO "Device.X_ADB_LED.ServiceLED.[Enable=true].Behaviour.Trigger.[Operator="CountObj_\>"]"
			for countobjs in $countobjs; do
				cmclient -v value GETO "%($countobjs.Parameter)"
				if [ ${#value} -gt 0 ]; then
					for value in $value; do
						[ "$value" = "$obj" ] && LEDs=${countobjs%.Behaviour*} && break
					done
				fi
				[ ${#LEDs} -gt 0 ] && break
			done
		fi
	else
		cmclient -v LEDs GETO "Device.X_ADB_LED.ServiceLED.[Enable=true]"
	fi
fi
[ ${#LEDs} -gt 0 ] || exit 0
. /etc/ah/helper_serialize.sh && help_serialize Led
match=0
for LED in $LEDs; do
	cmclient -v behaviour GETO "$LED.Behaviour.[Enable=true]"
	for behaviour in $behaviour; do
		match=1
		cmclient -v triggers GETO "$behaviour.Trigger.[Enable=true]"
		for trigger in $triggers; do
			cmclient -v parameterOp GETV "${trigger}.Operator"
			cmclient -v parameterPath GETV "${trigger}.Parameter"
			case "$parameterOp" in
			"CountObj_>" | "ObjPresent" | "ObjNotPresent")
				GET="GETO"
				;;
			*) GET="GETV" ;;
			esac
			cmclient -v parameterValue "$GET" "${parameterPath}"
			if [ "$parameterOp" = "CountObj_>" ]; then
				countObj "$parameterValue"
				parameterValue=$?
			fi
			cmclient -v parameterMatch GETV "${trigger}.Value"
			evaluateCondition "${parameterOp}" "${parameterValue}" "${parameterMatch}"
			if [ $? -eq 0 ]; then
				match=0
				break
			fi
		done
		if [ $match -eq 1 ]; then
			cmclient -v name GETV ${LED}.Name
			cmclient -v colour GETV ${behaviour}.Colour
			cmclient -v dutyCycle GETV ${behaviour}.DutyCycle
			cmclient -v activityReference GETV ${behaviour}.ActivityReference
			cmclient SET "${LED}.CurrentColour" "$colour"
			setLED
			break
		fi
	done
	if [ $match -eq 0 ]; then
		cmclient -v name GETV ${LED}.Name
		cmclient -v colour GETV ${LED}.DefaultColour
		cmclient -v dutyCycle GETV ${LED}.DefaultDutyCycle
		cmclient -v activityReference GETV ${LED}.ActivityReference
		cmclient SET "${LED}.CurrentColour" "$colour"
		setLED
	fi
done
exit 0
