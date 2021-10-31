#!/bin/sh
. /etc/ah/helper_ipsec.sh
[ $changedX_ADB_IPsecAccessCapable -eq 0 ] && exit 0
cmclient -v currentUsername GETV $obj.Username
cmclient -v i GETV Device.Users.User.+.[Enable=true].[X_ADB_IPsecAccessCapable=true].Username
for i in $i; do
[ "$i" != "$currentUsername" ] && ipsec_user_list="${ipsec_user_list},${i}"
done
[ "$newX_ADB_IPsecAccessCapable" = "true" ] && \
ipsec_user_list=${currentUsername}${ipsec_user_list} || \
ipsec_user_list=${ipsec_user_list#,}
c_hdr="${IPSEC_GROUP}:x:${IPSEC_GROUP_ID}:"
sed s/${c_hdr}.*/${c_hdr}${ipsec_user_list}/ $GROUP_FILE > $TEMP_GROUP_FILE && \
mv $TEMP_GROUP_FILE $GROUP_FILE
cmclient -v ipsec_enabled GETV Device.IPsec.Enable
cmclient -v xauth_enabled GETO Device.IPsec.Filter.*.[Enable=true].X_ADB_RoadWarrior.[Enable=true].[Type=XAuth]
[ "$ipsec_enabled" = "true" -a ${#xauth_enabled} -gt 0 ] &&  ipsec_commit
exit 0
