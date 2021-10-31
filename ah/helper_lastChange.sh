#!/bin/sh
help_lastChange_get() {
local uptime lastChange
cmclient -v lastChange GETV "$1.X_ADB_LastChange"
IFS=. read -r uptime _ < /proc/uptime
[ -n "$lastChange" ] && lastChange=$((uptime - lastChange)) || cmclient -v lastChange GETV Device.DeviceInfo.UpTime
echo $lastChange
}
help_lastChange_set() {
local uptime
IFS=. read -r uptime _ < /proc/uptime
cmclient SETE "$1.X_ADB_LastChange" $uptime
}
