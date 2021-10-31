#!/bin/sh
AH_NAME="VoIPC2D"
VOIP_CTRLIF_ADDR="local:/tmp/voip_socket"
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize
service_config() {
	local _si _pi _li _cp _ei _ep _caller
	if [ "$setEnable" = "1" -a "$newEnable" = "true" ]; then
		cmclient -v _cp GETV "$obj.CalledPartyNumber"
		cmclient -v _ep GETV "$obj.FromVoicePort"
		cmclient -v _ei GETV "%($obj.FromVoicePort).InterfaceID"
		if [ -z "$_ei" ]; then
			_si=${_ep%%.VoiceProfile*}
			_si=${_si##*VoiceService.}
			_pi=${_ep%%.Line*}
			_pi=${_pi##*VoiceProfile.}
			_li=${_ep##*Line.}
			cmclient -v _caller GETV "$_ep.DirectoryNumber"
			echo C2D ${_si}.${_pi}.${_li} ${_cp} ${_caller} ${_ei} | nc $VOIP_CTRLIF_ADDR
		else
			_si=${obj%%.X_ADB_SIP.Dialer*}
			_si=${_si##*VoiceService.}
			cmclient -v _li GETO "Services.VoiceService.${_si}.VoiceProfile.Line.[Status=Up].[PhyReferenceList>${_ei}]"
			for _li in $_li; do
				cmclient -v _caller GETV "$_li.DirectoryNumber"
				_pi=${_li%%.Line.*}
				_pi=${_pi##*VoiceProfile.}
				_li=${_li##*.}
				echo C2D ${_si}.${_pi}.${_li} ${_cp} ${_caller} ${_ei} | nc $VOIP_CTRLIF_ADDR
				break
			done
		fi
	fi
	return 0
}
case "$op" in
s)
	service_config
	;;
esac
exit 0
