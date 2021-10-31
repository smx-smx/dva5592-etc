#!/bin/sh
#nl:add,module,bcm_enet
. /etc/ah/target.sh
wait_set_sched_affinity "bcmsw_rx" "r-5"
wait_set_sched_affinity "bcmsw_rx" "a-1"
ethctl phy serdespower eth0 2
