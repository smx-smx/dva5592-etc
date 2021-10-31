#! /bin/sh
lookupIPAddress() {
	mac=$1
	for i in $(cmclient GETO Hosts.Host); do
		physaddr=$(cmclient GETV "$i.PhysAddress")
		if [ "$mac" = "$physaddr" ]; then
			echo -n "$(cmclient GETV $i.IPAddress)"
			return
		fi
	done
}
if [ $changedTypeOfRestriction -eq 1 ]; then
	blocked=$(cmclient GET "$obj.Blocked")
	if [ $newTypeOfRestriction = "NONE" ]; then
		Enforcement="NONE"
	else
		if [ $newTypeOfRestriction = "GUESTNETWORK" ]; then
			Enforcement="INTERNETONLY"
		else
			if [ $newTypeOfRestriction = "BLACKLIST" ]; then
				Enforcement="BLOCKED"
			else
				if [ $newTypeOfRestriction = "TIMEOFDAY" ]; then
					if [ $blocked = "true" ]; then
						Enforcement="LANONLY"
					else
						Enforcement="NONE"
					fi
				fi
			fi
		fi
	fi
	ip=$(lookupIPAddress $oldMACAddress)
	logger -t "HNDP" -p 6 "restriction:updated Type=\"$newTypeOfRestriction\" MacAddr=\"$oldMACAddress\" IpAddr=\"$ip\" Enforcement=\"$Enforcement\""
fi
if [ $changedBlocked -eq 1 ]; then
	if [ $oldTypeOfRestriction = "TIMEOFDAY" ]; then
		if [ $newBlocked = "true" ]; then
			Enforcement="LANONLY"
		else
			Enforcement="NONE"
		fi
	fi
	ip=$(lookupIPAddress $oldMACAddress)
	logger -t "HNDP" -p 6 "restriction:enforcementChange Type=\"$newTypeOfRestriction\" MacAddr=\"$oldMACAddress\" IpAddr=\"$ip\" Enforcement=\"$Enforcement\""
fi
exit 0
