#!/bin/sh
AH_NAME="ExecEnv"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
service_list_repository() {
local _execenv=$1
local _ret=0
eename=`cmclient GETV $_execenv.Name`
if [ "$eename" = "Linux" ]; then
opkg list | sed -e "s/ - /:/"
_ret=$?
fi
return $_ret
}
service_update_repository() {
local _execenv=$1
local _ret=0
eename=`cmclient GETV $_execenv.Name`
if [ "$eename" = "Linux" ]; then
opkg update > /dev/null
_ret=$?
opkg list | sed -e "s/ - /:/"
fi
return $_ret
}
service_config() {
if [ "$changedX_ADB_RepositoryURL" = "1" ]; then
help_execenv_repository $obj "$newX_ADB_RepositoryURL"
fi
if [ "$setEnable" = "1" ]; then
help_execenv_check $obj "$newEnable" "$newX_ADB_SecurityEnable" "$newAllocatedMemory" keep
fi
if [ "$setReset" = "1" -a "$newReset" = "true" ]; then
help_execenv_check $obj false $newX_ADB_SecurityEnable $newAllocatedMemory flush
help_execenv_reset $obj
help_execenv_check $obj $newEnable $newX_ADB_SecurityEnable $newAllocatedMemory
fi
}
service_get() {
local arg="$1"
case "$arg" in
Status)
echo $execenv_status
;;
AllocatedMemory)
echo $execenv_allocated_mem
;;
AvailableMemory)
echo $execenv_available_mem
;;
X_ADB_UpTime)
echo $execenv_uptime
;;
esac
}
load_helper() {
local obj="$1"
cmclient -v eename GETV "$obj.Name"
if [ "$eename" = "Linux" ]; then
. /etc/ah/helper_execenv_linux.sh
elif [ "$eename" = "OSGi" ]; then
. /etc/ah/helper_execenv_osgi.sh
elif [ "$eename" = "Docker" ]; then
. /etc/ah/helper_execenv_docker.sh
elif [ "$eename" = "LXC" ]; then
. /etc/ah/helper_execenv_lxc.sh
else
exit 0
fi
}
load_helper "$obj"
case "$op" in
g)
help_execenv_status "$obj"
for arg
do
service_get "$arg"
done
;;
s)
service_config
;;
d)
;;
a)
;;
esac
exit 0
