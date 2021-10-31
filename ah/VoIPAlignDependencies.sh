#!/bin/sh
AH_NAME="VoIPAlignDependencies"
VOICE_SERVICE="Device.Services.VoiceService.[X_ADB_Enable!false]"
[ "$op" = 's' ] && . /etc/ah/helper_serialize.sh && help_serialize > /dev/null
setm_args=""
trcd() {
local ret_name="$1" set="$2" arg="$3" ret='' tmp=''
[ ${#set} -eq 0 ] && return 1
while [ ${#arg} -ne 0 ]; do
while [ ${#arg} -ne 0 ]; do
tmp="$arg"
arg=${arg#[!$set]}
[ "$arg" = "$tmp" ] && break
done
while [ ${#arg} -ne 0 ]; do
tmp=`expr match "$arg" "\([$set]\)"`
[ ${#tmp} -eq 0 ] && break
ret="$ret$tmp"
arg=${arg#[$set]}
done
done
eval $ret_name='$ret'
}
line_id=""
get_line_id() {
local line_path="$1" dir_num="$2" sip_uri="$3"
line_id=""
[ "$dir_num" = 'g' ] && cmclient -v dir_num GETV "$line_path.DirectoryNumber"
[ -n "$dir_num" ] && line_id=`expr "$dir_num" : '\([0-9 \\\+-]\+\)$'`
if [ -z "$line_id" ]; then
[ "$sip_uri" = 'g' ] && cmclient -v sip_uri GETV "$line_path.SIP.URI"
if [ -n "$sip_uri" ]; then
line_id=`expr "$sip_uri" : 'sip:\([0-9 \\\+-]\+\)@'`
[ -z "$line_id" ] && line_id=`expr "$sip_uri" : 'sip:\([0-9 \\\+-]\+\)$'`
fi
fi
[ -n "$line_id" ] && return 0 || return 1
}
msn=""
get_msn() {
local line_path="$1" dir_num="$2" sip_uri="$3"
msn=""
get_line_id "$line_path" "$dir_num" "$sip_uri" && msn="$line_id" || return 1
trcd msn '0-9' "$msn"
[ -n "$msn" ] && return 0 || return 1
}
align_phy_referencies() {
local in_fxs_line_key="$1" fxs="$2" lines="" line="" \
line_key="" new_phy_ref="" old_phy_ref="" is_associated=""
cmclient -v lines GETO "$VOICE_SERVICE.VoiceProfile.[Enable!Disabled].Line.[Enable!Disabled]"
for line in $lines; do
cmclient -v line_key GETV "$line.DirectoryNumber"
cmclient -v old_phy_ref GETV "$line.PhyReferenceList"
new_phy_ref=""
case ,"$in_fxs_line_key", in
*,$line_key,* | ",,") is_associated="$line_key";;
*) is_associated="";;
esac
if [ "$fxs" = "1" ]; then
[ -n "$is_associated" ] && new_phy_ref="1,"
case  ,"$old_phy_ref", in
*,2,*) new_phy_ref="${new_phy_ref}2,";;
esac
elif [ "$fxs" = "2" ]; then
case  ,"$old_phy_ref", in
*,1,*) new_phy_ref="1,";;
esac
[ -n "$is_associated" ] && new_phy_ref="${new_phy_ref}2,"
fi
new_phy_ref="${new_phy_ref}3,4"
[ "$new_phy_ref" = "$old_phy_ref" ] || \
setm_args="$setm_args$line.PhyReferenceList=$new_phy_ref	"
done
}
align_msn() {
local line="$1" dir_num="$2" sip_uri="$3" new_msn="" old_msn=""
get_msn "$line" "$dir_num" "$sip_uri"
new_msn="$msn"
cmclient -v old_msn GETV "$line.X_ADB_MSN"
[ "$old_msn" = "$new_msn" ] && return
setm_args="$setm_args$line.X_ADB_MSN=$new_msn	"
}
align_dependencies() {
local line_path="" auto_msn="" phy_idx="" fxs1_key="" fxs2_key=""
setm_args=""
case "$obj" in
Device.Services.VoiceService.*.VoiceProfile.*.Line.*.SIP)
if [ "$setURI" = '1' ]; then
line_path="${obj%.SIP}"
cmclient -v auto_msn GETV "$line_path.X_ADB_AutoMSN"
[ "$auto_msn" = 'true' ] && align_msn "$line_path" 'g' "$newURI"
fi
;;
Device.Services.VoiceService.*.VoiceProfile.*.Line.*)
if [ "$setDirectoryNumber" = '1' ]; then
line_path="$obj"
cmclient -v auto_msn GETV "$line_path.X_ADB_AutoMSN"
[ "$auto_msn" = 'true' ] && align_msn "$line_path" "$newDirectoryNumber" 'g'
fi
;;
Device.Services.VoiceService.*.PhyInterface.*)
if [ "$setX_ADB_ReservedLineId" = '1' ]; then
phy_idx=${obj##*.}
if [ "$phy_idx" = "1" -o "$phy_idx" = "2" ]; then
local line_id='' rsv_line_id='' tmp=''
IFS=,
for line_id in $newX_ADB_ReservedLineId; do
cmclient -v tmp GETO "$VOICE_SERVICE.VoiceProfile.*.[Enable!Disabled].Line.*.[Enable!Disabled].[DirectoryNumber=$line_id]"
[ ${#tmp} -ne 0 ] && rsv_line_id="${rsv_line_id:+$rsv_line_id,}$line_id"
done
unset IFS
align_phy_referencies "$rsv_line_id" "$phy_idx"
fi
fi
;;
esac
setm_args=${setm_args%	}
if [ -n "$setm_args" ]; then
cmclient SETEM "$setm_args"
. /etc/ah/helper_cm.sh && help_cm_save now weak
fi
}
case "$op" in
s)
align_dependencies
;;
esac
exit 0
