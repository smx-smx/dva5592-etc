#!/bin/sh
AH_NAME="SW-ExecutionUnit"
if [ -n "$newRequestedState" ]; then
	eeobj=$(cmclient GETV ${obj}.ExecutionEnvRef)
	if [ -n "$eeobj" ]; then
		eename=$(cmclient GETV ${eeobj}.Name)
		if [ "$(cmclient GETV ${eeobj}.Enable)" = "false" ]; then
			echo "### ${AH_NAME}: Cannot change state of ${obj}: ExecEnv is disabled"
			exit 24
		fi
		if [ "$eename" = "OSGi" ]; then
			euid=$(cmclient GETV ${obj}.EUID)
			if [ "$newRequestedState" = "Active" ]; then
				echo "### ${AH_NAME}: Starting unit ${euid}"
				osgicli start ${euid}
			elif [ "$newRequestedState" = "Idle" ]; then
				echo "### ${AH_NAME}: Stopping unit ${euid}"
				osgicli stop ${euid}
			fi
			if [ "$?" != 0 ]; then
				echo "### ${AH_NAME}: Got error $? from osgicli"
			fi
		elif [ "$eename" = "Docker" ]; then
			local dunit image_name cont_name host_ip host_obj
			cmclient -v dunit GETO "Device.SoftwareModules.DeploymentUnit.[ExecutionUnitList<${obj}]"
			cmclient -v image_name GETV ${dunit}.Name
			cmclient -v cont_name GETV ${obj}.Name
			cmclient -v host_obj GETV ${obj}.X_ADB_VirtualHostRef
			if [ "$newRequestedState" = "Active" ]; then
				docker run -d --name=${cont_name} ${image_name}
				if [ "$?" -eq "0" ]; then
					cmclient SETE ${obj}.Status Active
					host_ip=$(docker inspect --format '{{.NetworkSettings.IPAddress}}' ${cont_name})
					cmclient SET ${host_obj}.IPAddress ${host_ip}
					cmclient SET ${host_obj}.Active true
				else
					echo "### ${AH_NAME}: Got error $? from docker during creating container"
					exit 1
				fi
			elif [ "$newRequestedState" = "Idle" ]; then
				docker rm -f ${cont_name}
				cmclient SETE ${obj}.Status Idle
				cmclient SET ${host_obj}.Active false
			fi
		elif [ "$eename" = "LXC" ]; then
			cmclient -v cont_name GETV ${obj}.Name
			if [ "$newRequestedState" = "Active" ]; then
				lxc-start -n ${cont_name}
				[ "$?" -eq 0 ] && cmclient SETE ${obj}.Status Active
			elif [ "$newRequestedState" = "Idle" ]; then
				lxc-stop -n ${cont_name}
				[ "$?" -ne 1 ] && cmclient SETE ${obj}.Status Idle
			fi
		fi
	fi
fi
exit 0
