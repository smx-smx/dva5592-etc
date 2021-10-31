#!/bin/sh
#nl:change,platform,regulatory*
country="$A1"
echo "eh_regulatory.sh: country $country"
COUNTRY=$country /sbin/crda
