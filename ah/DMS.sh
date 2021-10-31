#!/bin/sh
AH_NAME="DMS"
[ "$user" = "${AH_NAME}${obj}" ] && exit 0
[ "$op" != "g" ] && . /etc/ah/helper_serialize.sh && help_serialize > /dev/null
. /etc/ah/helper_functions.sh
ROOT_DIR="/tmp/dms/"
LOG_FILE="dms.log"
DOWNLOAD_FILE="restore.xml"
XML_FILE="plain.xml"
alias="DMSCheckInterval"
time_path="Device.X_ADB_Time.Event"
enable_dms() {
local enable=$1 check_interval=$2 setm_params=""
if [ "$enable" = "false" ]; then
cmclient DEL "${time_path}.[Alias>${alias}]"
else
if [ $check_interval -gt 0 ]; then
local idx action_path
cmclient -v idx ADDS ${time_path}
time_path="${time_path}.${idx}"
setm_params="${time_path}.Alias=${alias}${idx}"
setm_params="${setm_params}	${time_path}.Enable=true"
setm_params="${setm_params}	${time_path}.Type=Periodic"
setm_params="${setm_params}	${time_path}.DeadLine=${check_interval}"
cmclient -v idx ADDS "${time_path}.Action"
action_path="${time_path}.Action.${idx}"
setm_params="$setm_params	${action_path}.Path=Device.X_ADB_DMS.PerformDownload"
setm_params="$setm_params	${action_path}.Value=true"
cmclient SETM "${setm_params}"
fi
fi
}
update_check_interval() {
local enable=$1 check_interval=$2 timer
if [ "$enable" = "true" ]; then
cmclient -v timer GETO "${time_path}.[Alias>${alias}]"
if [ ${#timer} -ne 0 ]; then
cmclient SET "${time_path}.DeadLine" "$check_interval"
else
enable_dms "$newEnable" "$newCheckInterval"
fi
else
cmclient DEL "${time_path}.[Alias>${alias}]"
fi
}
generate_filename() {
local file="$1" mac_address serial_number prefix suffix mac_address_dotted
case $file in
*"%MACADDRESS%"*)
cmclient -v mac_address_dotted GETV "Device.X_ADB_FactoryData.BaseMACAddress"
IFS=:
for n in $mac_address_dotted
do
mac_address=$mac_address$n
done
unset IFS
mac_address=`help_uppercase $mac_address`
ret=${file%%%*}${mac_address}${file##*%}
;;
*"%macaddress%"*)
cmclient -v mac_address_dotted GETV "Device.X_ADB_FactoryData.BaseMACAddress"
IFS=:
for n in $mac_address_dotted
do
mac_address=$mac_address$n
done
unset IFS
mac_address=`help_lowercase $mac_address`
ret=${file%%%*}${mac_address}${file##*%}
;;
*"%SERIALNUMBER%"*)
cmclient -v serial_number GETV "Device.X_ADB_FactoryData.SerialNumber"
ret=${file%%%*}${serial_number}${file##*%}
;;
*"%"*"%"*)
return 1
;;
*)
ret=$file
return 0
;;
esac
return 0
}
fixup_template() {
local old_path="$1" new_path="$2"
while read line; do
case $line in
*"<Enable>Yes</Enable>"*)
echo "<Enable>Enabled</Enable>"
;;
*"<Enable>False</Enable>"*)
echo "<Enable>Disabled</Enable>"
;;
*)
echo "$line"
;;
esac
done < $old_path > $new_path
}
voip_reconf() {
user="" op=r /etc/ah/VoIPProfile.sh 1
user="" /etc/ah/VoIPIUA.sh r
}
apply_template() {
local path=$1
read -r md5 _ <<-EOF
`md5sum $path`
EOF
if [ "$md5" = "$newLastMD5" ]
then
cmclient SETE "${obj}.Status" "AllOk"
cmclient SETE "${obj}.ErrorMessage" "Template already applied"
exit 0
else
fixup_template "$path" "${path}_new"
mv "${path}_new" "${path}"
backup-restore -o restore -m full "$path" > ${ROOT_DIR}${XML_FILE}
if [ "$?" -eq 0 ]
then
mkdir "${ROOT_DIR}conf"
mv "${ROOT_DIR}${XML_FILE}" "${ROOT_DIR}conf"
cmclient CONF "${ROOT_DIR}conf/"
cmclient SETE "${obj}.LastMD5" "$md5"
cmclient SETE "${obj}.Status" "AllOk"
cmclient SETE "${obj}.ErrorMessage" ""
cmclient SAVE
else
cmclient SETE "${obj}.Status" "RestoreFailed"
cmclient SETE "${obj}.ErrorMessage" ""
exit 0
fi
fi
}
download_cfg() {
local retry=0 options=$1 max_retry
[ $newCheckInterval -le 60 ] && max_retry=0 || max_retry=3
while [ $retry -le $max_retry ]; do
retry=$(($retry+1))
yaft ${options} >  ${ROOT_DIR}${LOG_FILE}
if [ $? -ne 0 ]
then
read -r tmpstatus < "${ROOT_DIR}${LOG_FILE}"
cmclient SETE "${obj}.Status" "DownloadFailed"
cmclient SETE "${obj}.ErrorMessage" "$tmpstatus"
rm /tmp/dms.log
sleep 10
else
cmclient SETE "${obj}.PerformDownload" "false"
apply_template "${ROOT_DIR}${DOWNLOAD_FILE}"
voip_reconf
return 0
fi
done
cmclient SETE "${obj}.PerformDownload" "false"
exit 0
}
perform_download() {
local options="" path=$1 interface="" retry=0 tmpstatus=""
if [ -z "$newURL" ]
then
cmclient SETE "${obj}.Status MissingURL"
cmclient SETE "${obj}.ErrorMessage"  ""
cmclient SETE "${obj}.PerformDownload" "false"
exit 0
else
url=${newURL}
fi
if [ -n "$newFileName" ]
then
if ! generate_filename "${newFileName}"
then
cmclient SETE "${obj}.Status ConfigurationError"
cmclient SETE "${obj}.ErrorMessage" "Invalid file placeholder"
cmclient SETE "${obj}.PerformDownload" "false"
exit 0
fi
url=${url}/$ret
unset ret
fi
if [ -z "$path" ]
then
cmclient SETE "${obj}.Status ConfigurationError"
cmclient SETE "${obj}.ErrorMessage"  "Missing local path"
cmclient SETE "${obj}.PerformDownload" "false"
exit 0
fi
options="-d ${url}"
options="$options -o $path"
if [ -n "$newInterface" ]
then
help_lowlayer_ifname_get "interface" "$newInterface"
options="$options -i $interface"
fi
[ -n "$newUsername" -a -n "$newPassword" ] && options="$options -L ${newUsername}:${newPassword}"
case $newURL in
"https://"*)
options="$options -a /etc/certs/dms.pem"
;;
*)
:
;;
esac
download_cfg "$options" &
exit 0
}
service_config() {
if [ $changedEnable -eq 1 ]
then
enable_dms "$newEnable" "$newCheckInterval"
elif [ $changedCheckInterval -eq 1 ]
then
update_check_interval "$newEnable" "$newCheckInterval"
fi
if [ $changedPerformDownload -eq 1 -a "$newPerformDownload" = "true" ]
then
[ "$newEnable" = "false" ] && exit 0
[ "$newDownloaded" = "true" -a $newCheckInterval -eq 0 ] && exit 0
local default_route="" timer
cmclient -v default_route GETO Device.Routing.Router.**.IPv4Forwarding.[DestIPAddress=].[Enable=true]
[ ${#default_route} -eq 0 ] && \
cmclient -v default_route GETO Device.Routing.Router.**.IPv4Forwarding.[DestIPAddress=0.0.0.0].[DestSubnetMask=0.0.0.0].[Enable=true]
[ ${#default_route} -eq 0 ] && \
cmclient -v default_route GETV "Device.IP.Interface.[X_ADB_Upstream=true].IPv4Address.[Enable=true].IPAddress"
if [ ${#default_route} -eq 0 ]
then
cmclient SETE "${obj}.Status" "NoWAN"
cmclient SETE "${obj}.ErrorMessage" ""
exit 0
fi
cmclient -v timer GETO "${time_path}.[Alias>${alias}]"
[ ${#timer} -eq 0 ] && enable_dms "$newEnable" "$newCheckInterval"
[ ! -d "$ROOT_DIR" ] && mkdir -p "$ROOT_DIR"
perform_download "${ROOT_DIR}${DOWNLOAD_FILE}"
fi
}
if [ "$1" = "init" ]; then
local enable check_interval path="Device.X_ADB_DMS"
cmclient -v enable GETV ${path}.Enable
cmclient -v check_interval GETV ${path}.CheckInterval
enable_dms "$enable" "$check_interval"
exit 0
fi
case "$op" in
g)
for arg # Arg list as separate words
do
service_get "$obj.$arg"
done
;;
s)
service_config
;;
esac
exit 0
