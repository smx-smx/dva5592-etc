#!/bin/sh
CC_HOSTNAME="sam.sso.bluewin.ch"
AWK_SCRIPT='BEGIN {START=0;} /Name:/ {START=1;} /Address / {if (START==1) {split($0,a," ");print(a[3]);exit}}'
ATTEMPT=10
counter=0
while [ $counter -le $ATTEMPT ]; do
if nslookup "$CC_HOSTNAME" ; then
ip=`nslookup "$CC_HOSTNAME" | awk "$AWK_SCRIPT"`
cmclient SET "Device.X_ADB_ParentalControl.CustomerCenterIP" "$ip"
exit 0
else
counter=$(($counter + 1))
fi
done
exit 1
