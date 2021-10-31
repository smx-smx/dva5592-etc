#!/bin/sh
AH_NAME="PowerMng"
[ "$user" = "USER_SKIP_EXEC" ] && exit 0
service_pcie_pwsave() {
	local pcie="$newPciExpressPolicy"
	[ ${#newPciExpressPolicy} -eq 0 ] && pcie='default'
	[ -f /sys/module/pcie_aspm/parameters/policy ] && echo "$pcie" >/sys/module/pcie_aspm/parameters/policy
}
service_config() {
	local pconf
	pconf="--sr $newDRamSelfRefresh"
	pconf="$pconf --wait $newCpuR4kWait"
	pconf="$pconf --eee $newGlobalEEEEnable"
	pconf="$pconf --ethapd $newAPDEnable"
	pconf="$pconf --avs $newAdaptiveVoltageScaling"
	pconf="$pconf --cpuspeed $newCpuSpeed"
	pwrctl config $pconf
}
case "$op" in
s)
	[ -f /bin/pwrctl -a -x /bin/pwrctl -a "$newEnable" = 'true' ] && service_config
	service_pcie_pwsave
	;;
esac
exit 0
