#!/bin/sh
cmclient -v platsw GETV Device.DeviceInfo.X_ADB_PlatformSoftwareVersion
cmclient -v swver GETV Device.DeviceInfo.SoftwareVersion
cmclient -v addsw GETV Device.DeviceInfo.AdditionalSoftwareVersion
cmclient -v hwver GETV Device.X_ADB_FactoryData.HardwareVersion
cmclient -v manuf GETV Device.X_ADB_FactoryData.Manufacturer
cmclient -v model GETV Device.X_ADB_FactoryData.ModelName
gcctime=`cat /proc/version`
gcctime=${gcctime##*PREEMPT}
echo "SoftwareVersion:" $platsw-$addsw
echo "HardwareVersion:"	$hwver
echo "Manufacturer:"	$manuf
echo "ModelName:"	$model
echo "Compilation Time:" $gcctime
exit 0
