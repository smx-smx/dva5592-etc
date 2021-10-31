#!/bin/sh
DSLDIAG="dsldiagd"
if [ "$1" = "enable" ]; then
if pidof $DSLDIAG >/dev/null ; then
exit 0
else
$DSLDIAG &
fi
else
if [ "$1" = "disable" ]; then
killall -q $DSLDIAG
fi
fi
