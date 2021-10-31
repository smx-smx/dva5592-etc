#!/bin/sh
#nl:add,drivers,wl
. /etc/ah/target.sh
wait_set_sched_affinity wl1-kthrd a-2
wifiradio_hostapd_start
