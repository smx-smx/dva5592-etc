#!/bin/sh
log() {
echo $* >> /dev/console
echo $* >> /tmp/upgrade.log
logger -t "cm" -p 6 "Restore: $*"
}
get_input() {
local _ret1="$1" _res1="$2"
local _ret2="$3" _res2="$4"
[ -f "$_res1" ] || _res1="/tmp/conf.xml"
if [ ! -f "$_res1" ]; then
log "${_res1} not found"
return 1
fi
eval ${_ret1}='$_res1'
eval ${_ret2}='$_res2'
return 0
}
decrypt()  {
local _ret1="$1" _ret2="$2" _file="$3"
local _dst=/tmp/decrypted_$(basename $_file)
local _op=sym_decrypt
local _sharedkey=/etc/certs/download.pem
local _secretkey=/etc/certs/upload.pem
pkcrypt $_op $_sharedkey $_file > "$_dst"
if [ $? -ne 0 ]; then
log "Not a valid encrypted configuration file"
return 1
fi
if grep -q "<!-- DATA" $_dst; then
tr -d '\r' < "$_dst" | awk -v _dst="${_dst}" '/^<!-- DATA$/{flag=1 ; next} /^-->$/{if (flag) {next ; flag=0}} ; {if (flag) print > _dst "2"; else print > _dst "1"}' -
[ -f "${_dst}1" -a -f "${_dst}2" ] && base64 -d < "${_dst}2" | pkcrypt $_op $_secretkey - > "$_dst"
if [ $? -ne 0 ]; then
log "Not a valid encrypted configuration file"
return 1
else
rm -f "${_dst}2"
fi
else
base64 -d < "$_dst" | pkcrypt $_op $_secretkey - > "${_dst}2"
_dst=${_dst}2
fi
eval ${_ret1}='${_dst}1'
eval ${_ret2}='${_dst}'
return 0
}
detect_mode() {
local _ret="$1" _file="$2" _res
if [ -z "$_res" ]; then
_res=$(head -2 "$_file" | tail -1)
_res="${_res#<\!-- This is a \!}"
_res="${_res%\!*}"
fi
case "$_res" in
full|user*)
;;
*)
log "Unable to detect valid mode: $_res"
echo "fail_mode_detection" > /tmp/upgrade-result
return 1
;;
esac
eval ${_ret}='${_res}'
return 0
}
check_file_size() {
local _fsize _mode="$1" _file="$2"
_fsize=`wc -c <"$_file"`
if [ "$_mode" = "full" -a $_fsize -le 100000 ]; then
log "Unexpected 'full' mode"
return 1;
fi
return 0
}
base64_enc_section_restore() {
local _ret1="$1" _ret2="$2" _mode="$3" _file="$4" _validate_file="$5" _bckops _dst _ffile _vfile
_dst="/tmp/restore_$(basename $_file)"
_ffile="/etc/yaps-upgrade/${_mode}/restore.filters"
[ ${#_validate_file} -eq 0 ] && _validate_file="validate"
_vfile="/etc/yaps-upgrade/${_mode}/${_validate_file}.filters"
[ -f $_ffile ] && _bckops="-f $_ffile"
[ -f $_vfile ] && _bckops="$_bckops -v $_vfile"
backup-restore -o restore $_bckops "$_file" > "$_dst" 2>> /tmp/upgrade.log
if [ $? -ne 0 ]; then
log "Not a valid XML config file"
return 1
fi
eval ${_ret1}='${_dst}'
eval ${_ret2}='${_file}'
return 0
}
open_section_restore() {
local _ret=$1 _mode=$2 _file=$3 _openfile=$4 _bckops
local _dst="/tmp/restore_open_$(basename $_file)"
local _ffile="/etc/yaps-upgrade/${_mode}/open_restore.filters"
local _vfile="/etc/yaps-upgrade/${_mode}/open_validate.filters"
[ -f $_ffile ] && _bckops="$_bckops -f $_ffile"
[ -f $_vfile ] && _bckops="$_bckops -v $_vfile"
backup-restore -o restore -x "	" $_bckops "$_openfile" > "$_dst" 2>> /tmp/upgrade.log
if [ $? -ne 0 ]; then
log "Not a valid XML config file"
return 1
fi
eval ${_ret}='${_dst}'
return 0
}
selective_restore() {
local _section _mode=$1 _sfile=$2 _currentImage=$3 _validate_file=$4 _gui_lan_ip=$5
[ ${#_validate_file} -eq 0 ] && _validate_file="validate"
for _section in /tmp/selective-restore.*; do
if [ -e $_section ]; then
_section=${_section#/tmp/selective-restore.}
log "Restoring section: $_section"
backup-restore -o restore -f /etc/yaps-upgrade/${_mode}/restore_${_section}.filters -v /etc/yaps-upgrade/${_mode}/${_validate_file}.filters "${_sfile}" > /tmp/selective_${_section}.xml 2>> /tmp/upgrade.log
if [ $? -ne 0 ]; then
log "Not a valid XML config file"
return 1
fi
if [ "$_section" = "network_basic_settings" -a ${#_gui_lan_ip} -ne 0 ]; then
local found=0 first sec ip curr_ip
gui_lan_ip=""
while read -r first sec ; do
case "$first" in
\<value\>*\<\/value\> )
if [ $found -eq 2 ]; then
ip=${first%*</value>}
ip=${ip#*<value>}
cmclient -v curr_ip GETV "Device.IP.Interface.1.IPv4Address.1.IPAddress"
[ "$curr_ip" != "$ip" ] && eval ${_gui_lan_ip}='$ip'
break
fi
;;
esac
case "$sec" in
name\=\"Device.IP.Interface.1.IPv4Address.1\"\> )
found=1
;;
name\=\"IPAddress\"\> )
if [ $found -eq 1 ]; then
found=2
fi
;;
esac
done < /tmp/selective_network_basic_settings.xml
fi
fi
done
return 0
}
get_mtd_dev() {
local partition name
while read -r partition _ _ name ; do
case "$name" in
\"${2}\")
partition=${partition%:}
break
;;
esac
done < /proc/mtd
eval $1='/dev/mtdblock${partition#mtd}'
}
check_copy_success() {
get_mtd_dev cfgDevice conf_fs
umount $cfgDevice
mount -t yaffs $cfgDevice /tmp/cfg
for elem in $@; do
if ! find "${elem}"; then
return 1
fi
done
return 0
}
error_conf_bigger_than_partition() {
local _currentImage="$1"
log "New config too big. Restoring current config ${_currentImage}"
rm -rft /tmp/cfg "/tmp/cfg/${_currentImage}_new"
rm -rft /tmp/cfg "/tmp/cfg/${_currentImage}_override"
cmclient SAVE
}
apply_config_file_full() {
local _currentImage="$1" _file="$2"
mkdir -p /tmp/cfg/${_currentImage}_new/ 2>/dev/null
cp "$_file" /tmp/cfg/${_currentImage}_new/data.xml
cp /tmp/cfg/${_currentImage}/VendorConfig.xml /tmp/cfg/${_currentImage}_new/
check_copy_success "/tmp/cfg/${_currentImage}_new/data.xml"
if [ $? -ne 0 ]; then
error_conf_bigger_than_partition ${_currentImage}
return 1
fi
return 0
}
apply_config_file_user() {
local _currentImage="$1" _file="$2" _mode="$3"
mkdir -p /tmp/cfg/${_currentImage}_override/ 2>/dev/null
cp "${_file}" /tmp/cfg/${_currentImage}_override/${_mode}.xml
check_copy_success "/tmp/cfg/${_currentImage}_override/${_mode}.xml"
if [ $? -ne 0 ]; then
error_conf_bigger_than_partition ${_currentImage}
return 1
fi
return 0
}
apply_config_file_open() {
local _currentImage="$1" _openfile="$2"
mkdir -p /tmp/cfg/${_currentImage}_override/ 2>/dev/null
cp "$_openfile" /tmp/cfg/${_currentImage}_override/data1.xml
check_copy_success "/tmp/cfg/${_currentImage}_override/data1.xml"
if [ $? -ne 0 ]; then
error_conf_bigger_than_partition ${_currentImage}
return 1
fi
return 0
}
reset() {
local _mode=$1
cmclient STOP
sleep 3
[ "$_mode" = "full" ] && rm -rft /tmp/cfg /tmp/cfg/main /tmp/cfg/recovery /tmp/cfg/cache
log "Rebooting..."
reboot
}
cleanup() {
local _item _file=$1 _openfile=$2 _sfile=$3 _selective_filter=$4
rm -f "$_file"
rm -f "$_file"1
rm -f "$_openfile"
rm -f "$_sfile"
for _item in $_selective_filter; do
rm -f "$_item"
done
return 0
}
selective_files_exist () {
local _configfile
for _configfile in /tmp/selective_*.xml; do
[ -e $_configfile ] && return 0
done
return 1
}
apply_config_file_selective () {
local _currentImage="$1" _configfile
mkdir -p /tmp/cfg/${_currentImage}_override/ 2>/dev/null
for _configfile in /tmp/selective_*.xml; do
if [ -e $_configfile ]; then
mv $_configfile /tmp/cfg/${_currentImage}_override/
check_copy_success "/tmp/cfg/${_currentImage}_override/${_configfile#/tmp/}"
if [ $? -ne 0 ]; then
error_conf_bigger_than_partition ${_currentImage}
return 1
fi
fi
done
return 0
}
