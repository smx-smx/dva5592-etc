#!/bin/sh
cmclient -v users_list GETO "Device.Users.User.[X_ADB_Creator!System]"
for u in $users_list; do
cmclient -v uname GETV "$u.Username"
echo "Unknown User $uname... remove it!"
cmclient DEL "$u"
done
