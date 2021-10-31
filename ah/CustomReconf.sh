#!/bin/sh
custom_reconf() {
local interface="$1" if_status event_id action_id voip_enable_object="Device.Services.VoiceService.1.X_DLINK_Enable" voipRelay
cmclient -v if_status GETV "$interface".Status
if [ "$if_status" = "Up" ]; then
case $interface in
Device.IP.Interface*)
cmclient -v event_id ADDS Device.X_ADB_Time.Event.[Alias="DLink-EnableVoip"]
cmclient SETE Device.X_ADB_Time.Event.$event_id.DeadLine "20"
cmclient -v action_id ADDE Device.X_ADB_Time.Event.$event_id.Action.[Path="$voip_enable_object"]
cmclient SETE Device.X_ADB_Time.Event.$event_id.Action.$action_id.Value "true"
cmclient SET Device.X_ADB_Time.Event.$event_id.Enable "true"
;;
esac
fi
cmclient -v voipRelay GETO Device.DNS.Relay.Forwarding.[Interface=Device.IP.Interface.4]
[ ${#voipRelay} -ne 0 ] && cmclient SET "$voipRelay.Enable" "false"
}
