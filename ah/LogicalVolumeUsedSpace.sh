#!/bin/sh
service_get() {
local obj="$1" arg="$2"
case "$arg" in
UsedSpace)
local name status used=0
cmclient -v name GETV "$obj.Name"
cmclient -v status GETV "$obj.Status"
if [ "$status" = "Online" -a ${#name} -ne 0 ]; then
{
read -r _
read -r _ _ used _
} <<-EOF
`df -k $name`
EOF
fi
echo "$((used / 1024))"
;;
esac
}
case "$op" in
g)
for arg # Arg list as separate words
do
service_get "$obj" "$arg"
done
esac
exit 0
