#!/bin/sh
AH_NAME="helper_conf_upgrade.sh"
help_tr() {
local str1=$1
local str2=$2
set -f
[ -n "${IFS+x}" ] && local oldifs=$IFS || unset oldifs
IFS="$str1"
set -- $3
[ -n "${oldifs+x}" ] && IFS=$oldifs || unset IFS
set +f
[ -n "$1" ] || return
printf "%s" "$1"
shift
for arg; do
printf "%s%s" "$str2" "$arg"
done
}
verStr2verNum() {
local ver=$1
local maj=${ver%%.*} ; ver=${ver#*.}
local min=${ver%%.*} ; ver=${ver#*.}
local sub=${ver%%.*} ; ver=${ver#*.}
local build=${ver%%[A-Za-z-_.]*}
expr $maj \* 256 \* 256 \* 256 \* 256 + $min \* 256 \* 256 \* 256 + $sub \* 256 \* 256 + $build
}
incDecVersion() {
local maj min sub
IFS=. read -r maj min sub <<-EOF
$commonPart
EOF
if [ "$type" = "upgrade" ]; then
if [ $sub -eq 255 ]; then
if [ $min -eq 255 ]; then
commonPart="$((maj + 1)).0.0"
else
commonPart="$maj.$((min + 1)).0"
fi
else
commonPart="$maj.$min.$((sub + 1))"
fi
else
if [ $sub -eq 0 ]; then
if [ $min -eq 0 ]; then
commonPart="$((maj - 1)).255.255"
else
commonPart="$maj.$((min - 1)).255"
fi
else
commonPart="$maj.$min.$((sub - 1))"
fi
fi
}
doUpgrade() {
local prevCmp=`verStr2verNum "$1"`
local curCmp=`verStr2verNum "$2"`
commonPart=${1%.*}
local i=${1##*.}
i=${i%%[A-Za-z-_.]*}
local _commonFuncPart=`help_tr . _ "$commonPart"`
local _oldcommonPart=$commonPart
local _build _commonCmp=`verStr2verNum "$commonPart.0"`
if [ $prevCmp -lt $curCmp ]; then
type=upgrade
local _op=-le
i=`expr $i + 1`
elif [ $prevCmp -gt $curCmp ]; then
type=downgrade
local _op=-ge
i=`expr $i - 1`
else
return 0
fi
while :; do
_build=`printf "%.4d" "$i"`
if command -v ${4}${type}_${3}_${_commonFuncPart}_$_build >/dev/null; then
eval ${4}${type}_${3}_${_commonFuncPart}_$_build
fi
if command -v ${4}${type}_${_commonFuncPart}_$_build >/dev/null; then
eval ${4}${type}_${_commonFuncPart}_$_build
fi
[ $(($_commonCmp + $i)) -eq $curCmp ] && break
[ "$type" = "upgrade" ] && i=$((i + 1)) || i=$((i - 1))
[ $i -gt 10000 -o $i -lt 0 ] && incDecVersion
if [ "$commonPart" != "$_oldcommonPart" ]; then
case "$commonPart" in
*.*.*.*)
i=`expr ${commonPart##*.} + 0`
commonPart=${commonPart%.*}
;;
*)
[ "$type" = "upgrade" ] && i=1 || i=9999
;;
esac
_commonCmp=`verStr2verNum "$commonPart.0"`
_commonFuncPart=`help_tr . _ "$commonPart"`
fi
_oldcommonPart=$commonPart
done
return 0
}
