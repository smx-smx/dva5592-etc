#!/bin/sh
VOIP_SERVICE="Services.VoiceService.1"
VOIP_PROFILE="${VOIP_SERVICE}.VoiceProfile"

voip_line_status() {
profiles=`cmclient GETO "${VOIP_PROFILE}"`
format="%-5s | %20s | %15s | %20s | %15s | %20s | %7s\n"
printf "${format}" "Id" "Directory number" "Status" "Last Registration" "Call state" "Call waiting state" "Message"
for profile in $profiles
do
	profileId="${profile##*.}"
        for line in `cmclient GETO "${profile}.Line"`
        do
                lineId="${line##*.VoiceProfile.*.Line.}"
		enable=`cmclient GETV $line.Enable`
		status=`cmclient GETV $line.Status`
		lastup=`cmclient GETV $line.X_ADB_LastUp`
		callstate=`cmclient GETV $line.CallState`
		number=`cmclient GETV $line.DirectoryNumber`
		message=`cmclient GETV $line.CallingFeatures.MessageWaiting`
		cwstate=`cmclient GETV $line.CallingFeatures.CallWaitingStatus`
		printf "${format}" "${profileId}.${lineId}" "${number}" "${status}" "${lastup}" "${callstate}" "${cwstate}" "${message}"
        done
done
}

voip_test_show() {
local state selector phone vdc vac rloop offhook ren pstn line
line="$1"
testphy="Device.Services.VoiceService.1.PhyInterface.$line"
testobj="${testphy}.Tests"

support=`cmclient GETO "${testphy}`
if [ "$support" = "" ]; then
	printf "Interface %s not present\n" "${line}"
	return
fi

support=`cmclient GETO "${testobj}`
if [ "$support" = "" ]; then
	printf "Interface %s does not support tests\n" "${line}"
	return
fi

cmclient -v state GETV "${testobj}.TestState"
cmclient -v selector GETV "${testobj}.TestSelector"
cmclient -v phone GETV "${testobj}.PhoneConnectivity"
cmclient -v vdc GETV "${testobj}.X_ADB_Vloop_DC"
cmclient -v vac GETV "${testobj}.X_ADB_Vloop_AC"
cmclient -v rloop GETV "${testobj}.X_ADB_Rloop"
cmclient -v offhook GETV "${testobj}.X_ADB_OffHook"
cmclient -v ren GETV "${testobj}.X_ADB_REN"
cmclient -v pstn GETV "${testobj}.X_ADB_PSTN"
format="%-4s | %-10s | %-20s | %-10s | %-6s | %-6s | %-6s | %-7s | %-3s | %-5s\n"
printf "${format}" "Line" "State" "Test" "Phone" "VDC" "VAC" "RLoop" "Offhook" "Ren" "Pstn"
printf "${format}" "${line}" "${state}" "${selector}" "${phone}" "${vdc}" "${vac}" "${rloop}" "${offhook}" "${ren}" "${pstn}"
}

voip_line_show() {
profilePar="$1"
linePar="$2"
section="$3"
match=""
if [ "$profilePar" = "0" ]; then
	profiles=`cmclient GETO "${VOIP_PROFILE}"`
else
	profiles="${VOIP_PROFILE}.${profilePar}"
fi
for profile in $profiles
do
	profileId="${profile##*.}"
	if [ "$linePar" = "0" ]; then
		lines=`cmclient GETO "${profile}.Line"`
	else
		lines="${profile}.Line.${linePar}"
	fi

        for line in $lines
	do
                lineId="${line##*.VoiceProfile.*.Line.}"
		match="yes"
		case "$section" in
		"config")
			lineParams=`cmclient -u voip GET ${line}.`
			for param in $lineParams
			do
				ParameterName="${param%%;*}"
				# Strip longest match match of *. from front of value
				ParameterLeafName="${ParameterName##*.}"
				# Strip shortest match of *; from front of value
				ParameterValue="${param#*;}"
				ParameterObj=${ParameterName%.*}
				ParameterObj="${ParameterObj#*Line.[0-90-90-9]}"
				if [ "$ParameterObj" != "" ]; then
					ParameterObj="${ParameterObj#.}"
					ParameterObj="${ParameterObj%%.*}"
				fi
				case "$ParameterLeafName" in
				"Enable")
					 if [ "$ParameterObj" == "" ]; then
						Enable="$ParameterValue"
					fi;;
				"DirectoryNumber" | "AuthUserName" | "AuthPassword" | \
				"URI" | "PhyReferenceList" | \
                                "EchoCancellationEnable" | \
				"TransmitGain" | \
				"ReceiveGain" | \
				"CallerIDEnable" | \
				"CallerIDNameEnable" | \
				"CallerIDName" | \
				"CallWaitingEnable" | \
				"CallForwardUnconditionalEnable" | \
				"CallForwardUnconditionalNumber" | \
				"CallForwardOnBusyEnable" | \
				"CallForwardOnBusyNumber" | \
				"CallForwardOnNoAnswerEnable" | \
				"CallForwardOnNoAnswerNumber" | \
				"CallForwardOnNoAnswerRingCount" | \
				"CallTransferEnable" | \
				"MWIEnable" | \
				"AnonymousCallBlockEnable" | \
				"DoNotDisturbEnable" | \
				"RepeatDialEnable" | \
                                "X_ADB_CallHoldEnable" | \
				"X_ADB_PPrefIdEnable" | \
				"X_ADB_PPref" | \
				"X_ADB_ConferenceCallingEnable" | \
				"X_ADB_MWIType" | \
				"X_ADB_G726AAL2Coding" | \
				"X_ADB_AlertTimeout" | \
				"X_ADB_CallerIDPaiHeaderEnable" | \
				"X_ADB_EscapeDigits" )
					eval "$ParameterLeafName=\"$ParameterValue\"";;
                                *)
					;;
				esac
			done
			old_IFS=$IFS
			IFS=','
			intflist=""
			for phy in $PhyReferenceList; do
				intfs=`cmclient GETO Device.Services.VoiceService.1.PhyInterface.*.[InterfaceID="${phy}"]`
				IFS=$old_IFS
				for intf in $intfs
				do
					intfname=`cmclient GETV ${intf}.Description`
					intflist="${intfname} ${intflist}"
				done
				IFS=','
			done
			IFS=$old_IFS
			printf "Id=%-5s Directory Number=%s %s %s\n" "${profileId}.${lineId}" "${DirectoryNumber} ${Enable}"
			printf "%-20s : %s\n" "    Phy interfaces" "${intflist}"
			printf "%-20s : URI=%s  Username=%s Password=%s\n" \
							           "    SIP"  "${URI}" "${AuthUserName}" "${AuthPassword}"
			printf "%-20s : Escaped digits=%s\n"  " "  "${X_ADB_EscapeDigits}"
			[ "${X_ADB_CallerIDPaiHeaderEnable}" = "true" ] && printf "%-20s : P-asserted-identity=Enabled (for caller id)\n"  " "
			printf "%-20s : EchoCanceller=%s TransmitGain=%s ReceiveGain=%s\n" \
								   "    VoiceProcessing" "${EchoCancellationEnable}" "${TransmitGain}" "${ReceiveGain}"
			printf "%-20s :\n" "    Active features"
			[ "${CallerIDEnable}" = "true" ]                 && printf "%5s %-15s\n" "" "Caller Id"
			[ "${CallerIDNameEnable}" = "true" ]             && printf "%5s %-15s: Name=%s\n" "" "Caller Id Name:" "${CallerIDName}"
			[ "${X_ADB_CallHoldEnable}" = "true" ]           && printf "%5s %-15s\n" "" "Hold"
			[ "${CallWaitingEnable}" = "true" ]              && printf "%5s %-15s: Timeout=%s\n" "" "Call waiting:" "${X_ADB_AlertTimeout}"
			[ "${CallForwardUnconditionalEnable}" = "true" ] && printf "%5s %-15s: Number=%s\n" \
                                                                         "" "Call forward unconditional" "${CallForwardUnconditionalNumber}"
			[ "${CallForwardOnBusyEnable}" = "true" ]        && printf "%5s %-15s: Number=%s\n" "" "Call forward on busy" "${CallForwardOnBusyNumber}"
			[ "${CallForwardOnNoAnswerEnable}" = "true" ]    && \
                                 printf "%5s %-14s Number=%s RingCount=%s\n" "" "Call forward on no answer:" \
                                        "${CallForwardOnNoAnswerNumber}" "${CallForwardOnNoAnswerRingCount}"
			[ "${CallTransferEnable}" = "true" ]             && printf "%5s %-15s\n" "" "Call transfer"
                        [ "${MWIEnable}" = "true" ]                      && printf "%5s %-15s: Type=%s\n"  "" "Message waiting" "${X_ADB_MWIType}"
			[ "${X_ADB_PPrefIdEnable}" = "true" ]            && printf "%5s %-15s: Value=%s\n" "" "PPrefid" "${X_ADB_PPref}"
			[ "${X_ADB_ConferenceCallingEnable}" = "true" ]  && printf "%5s %-15s\n" "" "Conference call"
			[ "${AnonymousCallBlockEnable}" = "true" ]       && printf "%5s %-15s\n" "" "Anonymous call block"
			[ "${DoNotDisturbEnable}" = "true" ]             && printf "%5s %-15s\n" "" "Do not disturb"
			[ "${RepeatDialEnable}" = "true" ]               && printf "%5s %-15s\n" "" "Repeat dial"
			printf "%-20s :\n" "    Active codecs"
			codecs=`cmclient GETO "${line}.Codec.List"`
			for codec in $codecs
			do
				codecEnable=`cmclient -u voip GETV ${codec}.Enable`
				if [ "${codecEnable}" = "true" ]; then
					codecName=`cmclient -u voip GETV ${codec}.Codec`
					codecSS=`cmclient -u voip GETV ${codec}.SilenceSuppression`
					codecPtime=`cmclient -u voip GETV ${codec}.PacketizationPeriod`
					codecPriority=`cmclient -u voip GETV ${codec}.Priority`
					codecOpt=""
					if [ "${codecName}" = "G.726" -a "${X_ADB_G726AAL2Coding}" = "true" ]; then
						codecOpt="coding=AAL2"
					fi
					printf "%-20s : ptime=%-8s priority=%s vad=%s %s\n" \
						"      ${codecName}" "${codecPtime}" "${codecPriority}" "${codecSS}" "${codecOpt}"
				fi
			done
			;;
		"profile")
			;;
		"stat")
			DN=`cmclient -u voip GETV ${line}.DirectoryNumber`
			lineStats=`cmclient -u voip GET ${line}.Stats.`
			for stats in $lineStats
			do
				ParameterName="${stats%%;*}"
				# Strip longest match match of *. from front of value
				ParameterLeafName="${ParameterName##*.}"
				# Strip shortest match of *; from front of value
				ParameterValue="${stats#*;}"
				case "$ParameterLeafName" in
				"IncomingCallsReceived")  icRece="$ParameterValue";;
				"IncomingCallsAnswered")  icAnsw="$ParameterValue";;
				"IncomingCallsConnected") icConn="$ParameterValue";;
				"IncomingCallsFailed")    icFail="$ParameterValue";;
				"OutgoingCallsAttempted") ocAtte="$ParameterValue";;
				"OutgoingCallsAnswered")  ocAnsw="$ParameterValue";;
				"OutgoingCallsConnected") ocConn="$ParameterValue";;
				"OutgoingCallsFailed")    ocFail="$ParameterValue";;
				"CallsDropped")           caDrop="$ParameterValue";;
				"BytesSent")              bySent="$ParameterValue";;
				"BytesReceived")          byRece="$ParameterValue";;
				"PacketsSent")            paSent="$ParameterValue";;
				"PacketsReceived")        paRece="$ParameterValue";;
				"PacketsLost")            paLost="$ParameterValue";;
				"ReceivePacketLossRate")  rpLoss="$ParameterValue";;
				"FarEndPacketLossRate")            feLoss="$ParameterValue";;
				"ReceiveInterarrivalJitter")       reJitt="$ParameterValue";;
				"FarEndInterarrivalJitter")        feJitt="$ParameterValue";;
				"RoundTripDelay")                  rtDela="$ParameterValue";;
				"AverageReceiveInterarrivalJitter")avReJi="$ParameterValue";;
				"AverageFarEndInterarrivalJitter") avFeJi="$ParameterValue";;
				"AverageRoundTripDelay")           avRtDe="$ParameterValue";;
				esac
			done
			printf "Id=%-5s Directory Number=%s\n" "${profileId}.${lineId}" "${DN}"
			printf "   Incoming calls       : Received=%-3s  Answered=%-3s Connected=%-3s Failed=%-3s\n" \
						       "${icRece}" "${icAnsw}" "${icConn}" "${icFail}"
			printf "   Outgoing calls       : Attempted=%-3s Answered=%-3s Connected=%-3s Failed=%-3s\n" \
							"${ocAtte}" "${ocAnsw}" "${ocConn}" "${ocFail}"
			printf "   Dropped calls        : Total=%s\n" "${caDrop}"
			printf "   RTP total packets    : Sent=%-9s      Received=%-9s Lost=%-9s\n" "${paSent}" "${paRece}" "${paLost}"
			printf "   RTP total bytes      : Sent=%-9s      Received=%-9s\n" "${bySent}" "${byRece}"
			printf "   RTP Round Trip Delay : Current=%-9s   Average=%-9s\n"  "${rtDela}" "${avRtDe}"
			printf "   RTP Receive          : Loss Rate=%-9s Jitter=%-9s   Average Jitter=%-9s\n" "${rpLoss}" "${reJitt}" "${avReJi}"
			printf "   RTP Far End          : Loss Rate=%-9s Jitter=%-9s   Average Jitter=%-9s\n" "${feLoss}" "${feJitt}" "${avFeJi}"
			;;
		esac
	done
done
if [ "$match" = "" ]; then
	if [ "$linePar"  = "0" -a "$profilePar" = "0" ]; then
		printf "No configured lines\n"
	elif [ "$linePar" = 0 ]; then
		printf "No configured lines in profile %s\n" "${profilePar}"
	elif [ "$profilePar" = 0 ]; then
		printf "No configured lines with index %s\n" "${linePar}"
	else
		printf "No line %s in profile %s\n" "${linePar}" "${profilePar}"
	fi
fi
}

case "$1" in
	"status")
		voip_line_status
	;;
	"result")
		shift
		voip_test_show $*
	;;
	"line")
		shift
		voip_line_show $*
	;;
esac

exit 0
