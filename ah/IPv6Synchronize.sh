#!/bin/sh
AH_NAME="IPv6Synchronize"
refresh_prefix_lifetime() {
local uptime elem origin preferredLifetime prefixStatus validLifetime curr_sec addr setm='' setem=''
. /etc/ah/helper_serialize.sh && help_serialize "$AH_NAME" >/dev/null
curr_sec=`date -u +"%s"`
cmclient -v elem GETO "Device.IP.Interface.*.IPv6Prefix"
IFS=. read uptime _ < /proc/uptime
unset IFS
if [ ${#elem} -ne 0 ]; then
. /etc/ah/IPv6_helper_functions.sh
fi
for elem in $elem; do
cmclient -v origin GETV $elem.Origin
if [ "$origin" = "Static" ]; then
cmclient -v preferredLifetime GETV $elem.PreferredLifetime
cmclient -v validLifetime GETV $elem.ValidLifetime
else
cmclient -v preferredLifetime GETV "$elem.X_ADB_Preferred"
cmclient -v validLifetime GETV "$elem.X_ADB_Valid"
if [ ${#preferredLifetime} -ne 0 -a ${#validLifetime} -ne 0 -a $preferredLifetime -ne 0 -a \
$validLifetime -ne 0 ]; then
[ $preferredLifetime -gt $uptime ] && \
preferredLifetime=$((preferredLifetime - uptime)) || preferredLifetime=0
[ $validLifetime -gt $uptime ] && \
validLifetime=$((validLifetime - uptime)) || validLifetime=0
preferredLifetime=`help_ipv6_lft_from_secs $preferredLifetime $curr_sec`
validLifetime=`help_ipv6_lft_from_secs $validLifetime $curr_sec`
setem="${setem:+$setem	}$elem.PreferredLifetime=$preferredLifetime"
setem="${setem:+$setem	}$elem.ValidLifetime=$validLifetime"
setem="${setem:+$setem	}$elem.X_ADB_Preferred=0"
setem="${setem:+$setem	}$elem.X_ADB_Valid=0"
cmclient -v addr GETO "Device.IP.Interface.*.IPv6Address.[Prefix=$elem]"
for addr in $addr; do
setm="${setm:+$setm	}$addr.PreferredLifetime=$preferredLifetime"
setm="${setm:+$setm	}$addr.ValidLifetime=$validLifetime"
done
else
cmclient -v preferredLifetime GETV $elem.PreferredLifetime
cmclient -v validLifetime GETV $elem.ValidLifetime
fi
fi
if [ "$origin" = "Static" ]; then
prefixStatus=`get_status_from_lifetime "$preferredLifetime" "$validLifetime" "$elem"`
else
prefixStatus=`get_status_from_lifetime "$preferredLifetime" "$validLifetime" ""`
fi
setem="${setem:+$setem	}$elem.PrefixStatus=$prefixStatus"
if [ ${#setm} -gt 10000 -o ${#setem} -gt 10000 ]; then
[ ${#setm} -ne 0 ] && cmclient SETM "$setm" && setm=''
[ ${#setem} -ne 0 ] && cmclient SETEM "$setem" && setem=''
fi
done
[ ${#setm} -ne 0 ] && cmclient SETM "$setm"
[ ${#setem} -ne 0 ] && cmclient SETEM "$setem"
}
cmclient -v enable_tmp GETV "Device.IP.IPv6Enable"
if [ "$enable_tmp" = "true" ]; then
if [ "$changedStatus" = "1" ]; then
if [ "$newStatus" = "Synchronized" ]; then
refresh_prefix_lifetime
cmclient SET "Device.RouterAdvertisement.[Enable=true].Enable true"
cmclient SET "Device.DHCPv6.Server.[Enable=true].Enable true"
fi
fi
fi
exit 0
