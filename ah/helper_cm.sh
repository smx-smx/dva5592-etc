#!/bin/sh
help_cm_save() {
	local prio="$1"
	local mode="$2"
	local old_del old i evt delay alias
	old_del=""
	if [ "$mode" = 'weak' -o "$mode" = 'Weak' -o "$mode" = 'WEAK' ]; then
		mode=Weak
		case $prio in
		later | Later | LATER)
			cmclient -v old_del GETO "Device.X_ADB_Time.Event.[Alias>CMSaveWeak]"
			prio=Later
			;;
		*) # now
			cmclient -v old GETO "Device.X_ADB_Time.Event.[Alias>CMSaveWeakLater]"
			[ -n "$old" ] && return
			cmclient -v old_del GETO "Device.X_ADB_Time.Event.[Alias>CMSaveWeakNow]"
			prio=Now
			;;
		esac
	else # strict
		mode=Strict
		case $prio in
		later | Later | LATER)
			cmclient -v old GETO "Device.X_ADB_Time.Event.[Alias>CMSaveStrict]"
			[ -n "$old" ] && return
			prio=Later
			;;
		*) # now
			cmclient -v old GETO "Device.X_ADB_Time.Event.[Alias>CMSaveStrictNow]"
			[ -n "$old" ] && return
			cmclient -v old_del GETO "Device.X_ADB_Time.Event.[Alias>CMSaveStrictLater]"
			prio=Now
			;;
		esac
	fi
	for old in $old_del; do
		cmclient DEL "$old"
	done
	[ "$prio" = Later ] && delay=300 || delay=5
	cmclient -v i ADDS Device.X_ADB_Time.Event
	evt="Device.X_ADB_Time.Event.$i"
	alias="CMSave$mode$prio$i"
	cmclient -v i ADDS $evt.Action
	cmclient SETEM "$evt.Action.$i.Operation=Save"
	cmclient SETM "$evt.Alias=$alias	$evt.DeadLine=$delay	$evt.Type=Aperiodic	$evt.Enable=true"
}
help_cm_prune_path() {
	[ "$1" != 'b' ] && local b=''
	[ "$1" != 't' ] && local t=''
	set -f
	[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
	IFS='.'
	for t in $2; do
		case "$t" in
		*[!0-9]*) ;;
		*) t='{i}' ;;
		esac
		b=$b$t.
	done
	b=${b%.}
	[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
	set +f
	eval $1='$b'
}
