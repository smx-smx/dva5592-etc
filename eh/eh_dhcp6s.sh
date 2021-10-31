#!/bin/sh
#udp:*,dhcp6s,*
#sync:max=5,skipcycles

#
# this handler performs filling object model with yaps-dhcpv6 data about leased
# addresses.
#

AH_NAME="DHCPv6sEvHandler"

#
# per-object serialization
#
. /etc/ah/helper_serialize.sh && help_serialize "$AH_NAME" > /dev/null

#
# Remove duplication of this address assigned to other clients
#
address_deldup() {
	local pool_obj="$1" addr="$2" src="" ip=""

	# Remove address equal to this address assigned to other clients
	src="SourceAddress!${SOURCEADDRESS}"
	ip="IPAddress=${addr}"
	cmclient DEL "${pool_obj}.Client.*.[${src}].IPv6Address.*.[${ip}]"
}

#
# Remove duplication of this client in other pools.
# Duplication of a client object on a diffent pool can happens, for example,
# when it's plugged on eth3 (used by DMZ) and DMZ is enabled or when its
# network cable is moved from LAN to DMZ ports on CPE or viceversa.
#
client_deldup() {
	local client_pool="$1" client_addr="$2" pool="" client="" src=""

	cmclient -v pool GETO "Device.DHCPv6.Server.Pool"
	src="SourceAddress=${client_addr}"
	for pool in $pool; do
		if [ "$pool" != "$client_pool" ]; then
			local updated=0

			cmclient -v client GETO "${pool}.Client.*.[${src}]"
			for client in $client; do
				# Remove duplicated client
				cmclient DEL "${client}"
				updated=1
			done

			[ ${updated} -eq 1 ] && \
				/etc/ah/DHCPv6Server.sh clientchange "${pool}"
		fi
	done
}

#
# check IPAddress for the Client, add new IPAddress, update preferred and
# valid lifetime.
#
address_addset() {
	local _setm="$2" op_type="$3" cli_obj="$4" addr="$5" pref_time="$6" \
		valid_time="$7" pref_remain="$8" valid_remain="$9" iaid="$10" addr_objs

	# check addresses
	cmclient -v addr_objs GETO "${cli_obj}.IPv6Address.*.[IPAddress=${addr}]"
	if [ ${#addr_objs} -eq 0 -a "$op_type" = "create" ]; then
		cmclient -v addr_objs ADD "${cli_obj}.IPv6Address"
		addr_objs="${cli_obj}.IPv6Address.${addr_objs}"
		_setm="$_setm	${addr_objs}.IPAddress=${addr}"
		_setm="$_setm	${addr_objs}.X_ADB_IAID=${iaid}"
	fi

	for addr_objs in $addr_objs; do
		_setm="$_setm	${addr_objs}.PreferredLifetime=${pref_time}"
		_setm="$_setm	${addr_objs}.ValidLifetime=${valid_time}"
		_setm="$_setm	${addr_objs}.X_ADB_PreferredTimeRemaining=${pref_remain}"
		_setm="$_setm	${addr_objs}.X_ADB_ValidTimeRemaining=${valid_remain}"
	done

	eval $1='$_setm'
}

#
# check IPv6Prefix for the Client, add new IPv6Prefix, update preffered and valid lifetime
#
prefix_addset() {
	local _setm="$2" op_type="$3" cli_obj="$4" addr="$5" pref_time="$6" \
		valid_time="$7" pref_remain="$8" valid_remain="$9" iaid="$10" addr_objs

	# check addresses
	cmclient -v addr_objs GETO "${cli_obj}.IPv6Prefix.*.[Prefix=${addr}]"
	if [ ${#addr_objs} -eq 0 -a "$op_type" = "create" ]; then
		cmclient -v addr_objs ADD "${cli_obj}.IPv6Prefix"
		addr_objs="${cli_obj}.IPv6Prefix.${addr_objs}"
		_setm="$_setm	${addr_objs}.Prefix=${addr}"
		_setm="$_setm	${addr_objs}.X_ADB_IAID=${iaid}"
	fi

	for addr_objs in $addr_objs; do
		_setm="$_setm	${addr_objs}.PreferredLifetime=${pref_time}"
		_setm="$_setm	${addr_objs}.ValidLifetime=${valid_time}"
		_setm="$_setm	${addr_objs}.X_ADB_PreferredTimeRemaining=${pref_remain}"
		_setm="$_setm	${addr_objs}.X_ADB_ValidTimeRemaining=${valid_remain}"
	done

	eval $1='$_setm'
}




###########################################
#OP=CREATE
#CLIENT_DUID=0001000118c37b6efc7516cf7729
#SOURCEADDRESS=fe80::fe75:16ff:fecf:7729
#POOL_NAME=0
#IA_TYPE=IA_NA
#IAID=1
#IA_ENTRIES=2001:db8:1000::,90,120
###########################################
#OP=UPDATE
#CLIENT_DUID=0001000118c37b6efc7516cf7729
#SOURCEADDRESS=fe80::fe75:16ff:fecf:7729
#POOL_NAME=0
#IA_TYPE=IA_NA
#IAID=1
#IA_ENTRIES=2001:db8:1000::,90,120
###########################################

handle_create_or_update() {
	# 1) find the Pool object [DHCPv6.Server.Pool.{i}] by POOL_NAME
	# 2) check the Client object for the Pool first by the SourceAddress parameter
	# 3) add new Client object if there is no one existent
	# 4) parse IA_ENTRIES, for each entry:
	#  4.1) gets address/prefix, preffered and valid lifetime
	#  4.2) check the presence address/prefix in the IPv6Address or IPv6Prefix collection
	#  4.3) add or update IPv6Address or IPv6Prefix item

	local op_type="$1" pool_no=${POOL_NAME} pool_obj="" name="" intf="" \
	      saddress="" client_obj="" client_objs="" duid="" obj="" setm="" \
	      _uptime updated=0

	# find the Pool object [DHCPv6.Server.Pool.{i}] by POOL_NAME
	cmclient -v pool_obj GETO "Device.DHCPv6.Server.Pool.${pool_no}"

	[ ${#pool_obj} -eq 0 ] && return

	# Check the Client object for the Pool by the SourceAddress parameter.
	# Using this parameter we handle the following cases:
	# - a host has more then one interface (with same DUID)
	#   In this case, using distinct Client descriptors in the DOM, simplify
	#   their handling.
	# - a host's DHCPV6 client changes its DUID (it should not, but it can
	#   happens for example updating or reinstalling its OS or restoring to
	#   default its configuration). In this case, the SourceAddress remains
	#   the same, because generated by the MAC address of the network interface,
	#   and we have to update the client DUID. If we filtered clients by DUID,
	#   we would not find it and we would create a new client descriptor in the
	#   DOM, becoming the old one a zombie anymore reached and removed.
	# - the network hardware interface is moved to another host
	#   (so another DUID is bound to the same SourceAddress)
	cmclient -v client_objs GETO "${pool_obj}.Client.*.[SourceAddress=${SOURCEADDRESS}]"

	# If the client really does not exist and we create it, if requested.
	if [ ${#client_objs} -eq 0 -a "$op_type" = "create" ]; then
		# add new Client object
		cmclient -v client_objs ADD "${pool_obj}.Client"
		client_objs="${pool_obj}.Client.${client_objs}"

		# set SourceAddress and X_ADB_ClientDUID parameters
		setm="${client_objs}.SourceAddress=${SOURCEADDRESS}"
		setm="$setm	${client_objs}.X_ADB_ClientDUID=${CLIENT_DUID}"
		setm="$setm	${client_objs}.Active=true"
	else
		# If the client has been found, we update its DUID, if different.
		for client_obj in ${client_objs}; do
			cmclient -v duid GETV "${client_obj}.X_ADB_ClientDUID"
			[ "$duid" != "${CLIENT_DUID}" ] && \
				setm="${setm}${setm:+	}${client_obj}.X_ADB_ClientDUID=${CLIENT_DUID}"
		done
	fi

	if [ ${#client_objs} -ne 0 -a ${#IA_ENTRIES} -ne 0 ]; then
		# split IA_ENTRIES into address, preferred and valid lifetime
		IFS=. read _uptime _ < /proc/uptime
		setm="${setm:+$setm	}${client_objs}.X_ADB_RecordedTime=$_uptime"
		for ia_entry in ${IA_ENTRIES}; do
			set -f
			IFS=","
			set -- ${ia_entry}
			unset IFS
			set +f

			ia_addr=$1
			ia_pref_time_sec=$2
			ia_valid_time_sec=$3
			ia_id=${IAID}

			# convert time in seconds into 9999-12-31T23:59:59Z format
			# TODO: check the time values
			help_ipv6_lft_since_uptime ia_pref_time ${ia_pref_time_sec}
			help_ipv6_lft_since_uptime ia_valid_time ${ia_valid_time_sec}

			for client_obj in $client_objs; do
				case "${IA_TYPE}" in
				IA_NA)
					address_addset setm "$setm" "${op_type}" "${client_obj}" \
						"${ia_addr}" "${ia_pref_time}" "${ia_valid_time}" \
						"${ia_pref_time_sec}" "${ia_valid_time_sec}" "${ia_id}"
					[ "$op_type" = "create" ] && address_deldup "${pool_obj}" "${ia_addr}"
					;;
				IA_PD)
					prefix_addset setm "$setm" "${op_type}" "${client_obj}" \
						"${ia_addr}" "${ia_pref_time}" "${ia_valid_time}" \
						"${ia_pref_time_sec}" "${ia_valid_time_sec}" "${ia_id}"
					;;
				esac

				# If more than one pool is configured and client change pool (e.g. LAN to/from DMZ),
				# client is removed from the pool left.
				if [ "$op_type" = "create" ]; then
					cmclient -v pool_num GETV Device.DHCPv6.Server.PoolNumberOfEntries
					[ $pool_num -gt 1 ] && client_deldup "${pool_obj}" "${SOURCEADDRESS}"
				fi
			done
		done

		updated=1
	fi
	[ ${#setm} -ne 0 ] && cmclient SETM "$setm" >/dev/null

	# Command update of lease file
	[ ${updated} -eq 1 ] && /etc/ah/DHCPv6Server.sh clientchange "${pool_obj}"
}


############################################
#OP=RELEASE
#CLIENT_DUID=0001000118c37b6efc7516cf7729
#SOURCEADDRESS=fe80::fe75:16ff:fecf:7729
#POOL_NAME=0
#IA_TYPE=IA_NA
#IAID=0
#IA_ENTRIES=2001:db8:1000::,90,120
############################################
handle_release() {
	# 1) find the Pool object [DHCPv6.Server.Pool.{i}] by POOL_NAME
	# 2) check the Client object for the Pool by the SourceAddress property
	# 3) parse IA_ENTRIES, for each entry:
	#  3.1) gets address/prefix
	#  3.2) check the presence address/prefix in the IPv6Address or IPv6Prefix collection
	#  3.3) remove the item

	local pool_no=${POOL_NAME} pool_obj="" intf="" name="" saddress="" \
	      client_objs="" num_addr="" num_prefix=""

	# find the Pool object [DHCPv6.Server.Pool.{i}] by POOL_NAME
	cmclient -v pool_obj GETO "Device.DHCPv6.Server.Pool.${pool_no}"

	[ ${#pool_obj} -eq 0 ] && return

	# check the Client object for the Pool by the SourceAddress property
	cmclient -v client_objs GETO "${pool_obj}.Client.*.[SourceAddress=${SOURCEADDRESS}]"

	if [ ${#client_objs} -ne 0 -a ${#IA_ENTRIES} -ne 0 ]; then
		# split IA_ENTRIES into address, preffered and valid lifetime
		for ia_entry in ${IA_ENTRIES}; do
			set -f
			IFS=","
			set -- ${ia_entry}
			unset IFS
			set +f

			ia_addr=$1

			for client_obj in $client_objs; do
				case "${IA_TYPE}" in
				IA_NA)
					cmclient DEL ${client_obj}.IPv6Address.*.[IPAddress=${ia_addr}]
					;;
				IA_PD)
					cmclient DEL ${client_obj}.IPv6Prefix.*.[Prefix=${ia_addr}]
					;;
				esac

				# If no other addresses or prefixes belong to
				# client, it's removed.
				cmclient -v num_addr GETV ${client_obj}.IPv6AddressNumberOfEntries
				cmclient -v num_prefix GETV ${client_obj}.IPv6PrefixNumberOfEntries
				if [ $num_addr -eq 0 -a $num_prefix -eq 0 ]; then
					echo "no more addresses or prefixes: " \
					     "removing client ${client_obj}" \
					     > /dev/console
					cmclient DEL ${client_obj}
				fi
			done
		done

		# Command update of lease file
		/etc/ah/DHCPv6Server.sh clientchange "${pool_obj}"
	fi
}


option_update() {
	local cli_obj="$1" opt_tag="$2" opt_val="$3" opt_objs="" setm=""

	# check tag for "DHCPv6.Server.Pool.{i}.Client.{i}.Option.{i}"
	cmclient -v opt_objs GETO "${cli_obj}.Option.*.[Tag=${opt_tag}]"
	if [ ${#opt_val} -eq 0 ]; then
		for opt_objs in $opt_objs; do
			cmclient DEL ${opt_objs}
		done
	else
		if [ ${#opt_objs} -eq 0 ]; then
			cmclient -v opt_objs ADD "${cli_obj}.Option"
			opt_objs="${cli_obj}.Option.${opt_objs}"
			setm="${setm:+$setm	}${opt_objs}.Tag=${opt_tag}"
		fi

		for opt_objs in $opt_objs; do
			setm="${setm:+$setm	}${opt_objs}.Value=${opt_val}"
		done
		[ ${#setm} -ne 0 ] && cmclient SETM "$setm"
	fi
}


#############################################################################
#OP=INFORMATION
#CLIENT_DUID=0001000118c37b6efc7516cf7729
#SOURCEADDRESS=fe80::fe75:16ff:fecf:7729
#POOL_NAME=0
#OPTIONS="23"
#OPTION_23=20010db800000000000000000000000120010db8000000000000000000000002
#############################################################################

handle_info() {
	# 1) find the Pool object [DHCPv6.Server.Pool.{i}] by POOL_NAME
	# 2) check the Client object for the Pool by the SourceAddress property
	# 3) add new Client object if there is no one existent
	# 4) split OPTIONS into "tags"
	#  4.1) get OPTION_{tag} value
	#  4.2) check "tag" in the Device.DHCPv6.Server.Pool.{i}.Client.{i}.Option.{i} collection
	#  4.3) add new tag, update existent, remove empty

	local pool_no=${POOL_NAME} pool_obj="" client_objs=""

	# find the Pool object [DHCPv6.Server.Pool.{i}] by POOL_NAME
	cmclient -v pool_obj GETO "Device.DHCPv6.Server.Pool.${pool_no}"

	[ ${#pool_obj} -eq 0 ] && return

	# Check the Client object for the Pool by the SourceAddress property
	# (read above the reasons for use this property).
	# The update of DUID if was required is left to the handle_create_or_update.
	cmclient -v client_objs GETO "${pool_obj}.Client.*.[SourceAddress=${SOURCEADDRESS}]"

	if [ ${#client_objs} -eq 0 ]; then
		cmclient -v client_objs ADD "${pool_obj}.Client"
		client_objs="${pool_obj}.Client.${client_objs}"
		setm="${client_objs}.SourceAddress=${SOURCEADDRESS}"
		setm="$setm	${client_objs}.X_ADB_ClientDUID=${CLIENT_DUID}"
		setm="$setm	${client_objs}.Active=true"
		cmclient SETM "$setm"
	fi

	# split OPTIONS into "tags"
	for opt_tag in ${OPTIONS}; do
		# get option value for the "tag"
		eval "opt_value=\$OPTION_${opt_tag}"

		for client_objs in $client_objs; do
			option_update "${client_objs}" "${opt_tag}" "${opt_value}"
		done
	done
}


#
# adds and updates "Device.Hosts.Host" entries
# the code is based on "server.sh" script of "dibbler" package
#
host_entry_addset() {
	local setm="" mac="" ifn="" l1path="" l3path="" host_entries="" IPAddress=""

	mac=${CLIENT_HWADDR}
	ifn=$(interface_name_get "${INTERFACE}" ${mac})

	[ ${#ifn} -eq 0 ] && return

	l1path=$(help_obj_from_ifname_get "${ifn}")

	is_wan_intf "$l1path" && return

	l3path=$(ip_interface_get "${l1path}")

	cmclient -v host_entries GETO "Device.Hosts.Host.[PhysAddress=${mac}]"

	if [ ${#host_entries} -eq 0 ]; then
		cmclient -v host_entries ADD "Device.Hosts.Host"
		host_entries="Device.Hosts.Host.$host_entries"
	fi

	for entry in ${host_entries}; do
		setm="${setm:+$setm	}${entry}.Layer1Interface=${l1path}"
		setm="$setm	${entry}.Layer3Interface=${l3path}"
		setm="$setm	${entry}.PhysAddress=${mac}"

		# IPv4 AddressingType wins over IPv6, if present.
		cmclient -v IPAddress GETV ${entry}.IPAddress
		[ ${#IPAddress} -eq 0 ] && setm="$setm	${entry}.AddressSource=DHCP"

		# for each address in the IA_ENTRIES
		for ia_entry in ${IA_ENTRIES}; do
			set -f
			IFS=","
			set -- ${ia_entry}
			unset IFS
			set +f

			local ia_addr=$1

			local host_addr_obj
			cmclient -v host_addr_obj GETO "${entry}.IPv6Address.*.[IPAddress=${ia_addr}]"

			if [ ${#host_addr_obj} -eq 0 ]; then
				cmclient -v host_addr_obj ADD "${entry}.IPv6Address"
				host_addr_obj="${entry}.IPv6Address.$host_addr_obj"
			fi

			setm="$setm	${host_addr_obj}.IPAddress=${ia_addr}"
		done
	done

	cmclient SETM "$setm" >/dev/null
}

host_entry_delete() {
	local mac=${CLIENT_HWADDR}

	# for each address in the IA_ENTRIES
	for ia_entry in ${IA_ENTRIES}; do
		set -f
		IFS=","
		set -- ${ia_entry}
		unset IFS
		set +f

		local ia_addr=$1
		local entryList

		cmclient -v entryList GETO "Device.Hosts.Host.[PhysAddress=${mac}].[IPAddress=${ia_addr}]"
		for entry in $entryList; do
			cmclient DEL ${entry} >/dev/null
		done

		cmclient -v entryList GETO "Device.Hosts.Host.[PhysAddress=${mac}].IPv6Address.[IPAddress=${ia_addr}]"
		for entry in $entryList; do
			cmclient DEL ${entry} >/dev/null
		done
	done
}

save_duid () {
	cmclient SET "Device.DHCPv6.Server.X_ADB_DUID" "$1" >/dev/null
}

echo "$0: ${OP} ${POOL_NAME} ${CLIENT_HWADDR} ${SOURCEADDRESS} ${IA_TYPE} ${IA_ENTRIES}"

case ${OP} in
CREATE)
	. /etc/ah/helper_ifname.sh
	. /etc/ah/IPv6_helper_functions.sh
	handle_create_or_update "create"
	if [ "IA_NA" = ${IA_TYPE} ]; then
		. /etc/ah/helper_functions.sh
		host_entry_addset
	fi
	;;

UPDATE)
	. /etc/ah/helper_ifname.sh
	. /etc/ah/IPv6_helper_functions.sh
	handle_create_or_update "update"
	;;

RELEASE|EXPIRE)
	. /etc/ah/helper_ifname.sh
	handle_release
	if [ "IA_NA" = ${IA_TYPE} ]; then
		. /etc/ah/IPv6_helper_functions.sh
		host_entry_delete
	fi
	;;

INFORMATION)
	handle_info
	;;

SERVER_DUID)
	save_duid "$SERVER_DUID"
	;;

SAVE)
	. /etc/ah/helper_cm.sh
	help_cm_save 'now' 'weak'
	;;
esac
exit 0;

