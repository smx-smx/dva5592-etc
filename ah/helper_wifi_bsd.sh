#!/bin/sh
help_host_configured_to_use_bsd() {
local ret=0 mac=$1 video_sta_clients="" dual_band_sta_clients="" single_band_sta_clients=""
cmclient -v video_sta_clients GETV Device.WiFi.X_ADB_BandSteering.VideoSTA
cmclient -v dual_band_sta_clients GETV Device.WiFi.X_ADB_BandSteering.DualBandSTA
cmclient -v single_band_sta_clients GETV Device.WiFi.X_ADB_BandSteering.SingleBandSTA
if ! help_is_in_list $video_sta_clients $mac && \
! help_is_in_list $dual_band_sta_clients $mac && \
! help_is_in_list $single_band_sta_clients $mac; then
ret=1
fi
return $ret
}
help_store_host_which_uses_bsd() {
local mac_list="" mac="" hosts_obj="" storage_value
cmclient -v mac_list GETV "Device.Hosts.Host.PhysAddress"
for mac in $mac_list; do
storage_value=0
if help_host_configured_to_use_bsd $mac; then
storage_value=1
fi
cmclient -v hosts_obj GETO "Device.Hosts.Host.[PhysAddress=$mac]"
help_change_objects_storage_option $storage_value "$hosts_obj $hosts_obj.IPv4Address"
done
}
