#!/bin/sh
help_get_status_from_lowerlayers() {
[ "$1" != "arg" ] && local arg
[ "$1" != "new_status" ] && local new_status
[ ${#3} -eq 0 ] && cmclient -v arg GETV "$2.Enable" || arg="$3"
if [ "$arg" = "false" ]; then
eval $1='Down'
return
fi
[ ${#4} -eq 0 ] && cmclient -v arg GETV "$2.LowerLayers" || arg="$4"
[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
IFS=','
new_status=""
for arg in $arg; do
[ ${#5} -eq 0 ] && cmclient -v arg GETV "$arg.Status"
case $arg in
"Up" )
new_status="Up"
break
;;
"Error" )
new_status="Error"
;;
"Dormant" )
[ "$new_status" != "Error" ] && new_status="Dormant"
;;
"NotPresent" )
[ -z "$new_status" ] && new_status="NotPresent"
;;
"Down"|"LowerLayerDown" )
[ -z "$new_status" -o "$new_status" = "NotPresent" ] && new_status="LowerLayerDown"
;;
esac
done
[ -z "new_status" ] && new_status="LowerLayerDown"
[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
eval $1='$new_status'
}
