#!/bin/sh
AH_NAME="HostsPmUpdate.sh"
. /etc/ah/helper_functions.sh
update_pm_dmz() {
local obj_pm objs ah pm_ic ht_nn ht_mac
cmclient SET NAT.PortMapping.[Enable=true].[InternalClient=$newHostName].Enable true
cmclient SET NAT.PortMapping.[Enable=true].[InternalClient=$newPhysAddress].Enable true
cmclient SET NAT.PortMapping.[Enable=true].[InternalClient=$newIPAddress].Enable true
cmclient -v ah GETV Device.X_ADB_DMZ.X_ADB_AssociatedHost
[ "$ah" = "$obj" ] && cmclient SET Device.X_ADB_DMZ.IPAddress $newIPAddress
return 0
}
help_is_changed HostName PhysAddress IPAddress Active && update_pm_dmz
exit 0
