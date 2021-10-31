#!/bin/sh
help_cm_setm() {
help_cm_setx SETM "$@"
}
help_cm_setem() {
help_cm_setx SETEM "$@"
}
help_cm_setx() {
local x=2 _obj= setm=
while [ $x -lt $# ]; do
eval cmclient -v _obj GETO \${$x%.*}
for _obj in $_obj; do
eval setm='${setm:+$setm	}$_obj.'"\${$x##*.}"'=$'$((x + 1))
done
x=$((x + 2))
done
[ ${#setm} -ne 0 ] && cmclient -v _ "$1" "$setm"
}
