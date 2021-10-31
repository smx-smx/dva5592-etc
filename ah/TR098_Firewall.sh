#!/bin/sh
AH_NAME="TR098_Firewall"
[ "$user" = "cm181" ] && exit 0
service_get()
{
	en=`cmclient GETV Device.Firewall.Enable`
if [ "$en" = "true" ]; then
val=`cmclient GETV Device.Firewall.Config`
else
	val="Off"
fi
echo $val
}
service_set()
{
if [ "$newConfig" = "Off" ]; then
cmclient SET Device.Firewall.Enable "false" > /dev/null
else
if [ "$newConfig" = "High" ] || [ "$newConfig" = "Low" ]; then
cmclient SET Device.Firewall.Config $newConfig > /dev/null
cmclient SET Device.Firewall.Enable "true" > /dev/null
else
exit 7
fi
fi
}
case "$op" in
"s")
service_set
;;
"g")
service_get 
;;
esac
exit 0
