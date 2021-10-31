#!/bin/sh
#nl:add,module,dhd
. /etc/ah/target.sh
wait_set_sched_affinity dhd0_dpc a-1
