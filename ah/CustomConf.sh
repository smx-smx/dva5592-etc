#!/bin/sh
. /etc/ah/helper_functions.sh
AH_NAME="DefaultConf"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
. /etc/ah/helper_serialize.sh && help_serialize "CustomConf"
exeSaveCustomConf() {
local _obj= _objName= param= paramVal= paramName=
cmclient -v _obj GETO X_ADB_CustomConf.*.Object.[Action=Restore]
for _obj in $_obj; do
cmclient -v _objName GETV "$_obj.Name"
if [ ${#_objName} -ne 0 ]; then
cmclient -v param GETO "$_obj.Parameter"
for param in $param; do
cmclient -v paramName GETV "$param.Name"
cmclient -v paramVal GETV "$_objName.$paramName"
cmclient SET "$param.Value" "$paramVal"
done
fi
done
}
getValidObjName() {
local _ret="$1" _res="$2"
IFS="
"
set -- $_res
_res=$1
unset IFS
_res=${_res%%,*}
eval ${_ret}="$_res"
}
evaluateCMQuery() {
local _ret="$1" _res="$2"
_res=${_res#%(}
_res=${_res%)}
[ "$_res" != "$2" ] && cmclient -v _res GETV "${_res}"
eval ${_ret}="$_res"
}
exeRestoreCustomConf() {
local _objCustom="$1" _obj= _objName= param= action= _objCMD= objIdx= \
paramVal= paramName=
cmclient -v _obj GETV "${_objCustom}.Object.[Action=Delete].Name"
for _obj in $_obj; do
cmclient DEL "$_obj"
done
cmclient -v _obj GETO "${_objCustom}.Object.[Action!Delete]"
for _obj in $_obj; do
_objCMD=""
cmclient -v _objName GETV "$_obj.Name"
cmclient -v param GETO "$_obj.Parameter"
cmclient -v action GETV "$_obj.Action"
evaluateCMQuery "_objName" "${_objName}"
getValidObjName "_objName" "${_objName}"
case "$_objName" in
Device.*)
;;
*)
continue
;;
esac
if [ "$action" = "Add" ]; then
cmclient -v _objIdx ADD "$_objName"
[ "${_objName%.${_objIdx}}" != "$_objName" ] && _objName="$_objName.$_objIdx"
fi
for param in $param; do
cmclient -v paramName GETV "$param.Name"
cmclient -v paramVal GETV "$param.Value"
evaluateCMQuery "paramVal" "${paramVal}"
if [ ${#_objCMD} -eq 0 ]; then
_objCMD="$_objName.$paramName=$paramVal"
else
[ ${#paramVal} -ne 0 ] && _objCMD="$_objCMD	$_objName.$paramName=$paramVal"
fi
done
[ ${#_objCMD} -ne 0 ] && cmclient -u "$AH_NAME" SETM "$_objCMD"
done
[ "$user" != "boot" ] && cmclient SAVE
}
if [ "$1" = "save" ]; then
exeSaveCustomConf
else
case "$op" in
s)
case "$obj" in
"Device.X_ADB_CustomConf"*)
[ "$newApply" = "true" ] && exeRestoreCustomConf "$obj"
;;
esac
;;
esac
fi
exit 0
