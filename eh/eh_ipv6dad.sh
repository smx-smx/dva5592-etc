#!/bin/sh
#ipv6:*
if [ -n "$IFA_ADDRESS" -a "$IFA_F_DADFAILED" = "true" -a  "$RT_SCOPE" = LINK ]; then
cmclient -v obj GETO Device.Ethernet.Link.[Name=${IFA_IFNAME}]
cmclient -v iface GETO Device.IP.Interface.[LowerLayers=${obj}]
cmclient -v addr GETO ${iface}.IPv6Address.[IPAddress=$IFA_ADDRESS]
[ -n "$addr" ] && cmclient -v auto GETO ${addr}.[Origin=AutoConfigured]
if [ -z "$addr" -o -n "${auto}" ]; then
cmclient -v addresses GETO ${iface}.IPv6Address
for addr in $addresses; do
cmclient -u "eh_ipv6" SET ${addr}.Status "Error"
done
fi
fi
