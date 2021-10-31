#!/bin/sh /etc/rc.common
get_pdev() {
	local dev name
	while read -r dev _ _ name; do
		if [ "$name" = "\"$2\"" ]; then
			eval $1='${dev%:}'
			break
		fi
	done </proc/mtd
}
start() {
	local size partition rootMount currentImage osgipart
	mount proc /proc -t proc
	read _ size _ </proc/meminfo
	size=$((size * 512))
	mount tmpfs /tmp -t tmpfs -o size=$size,nosuid,nodev,mode=1777
	mount tmpfs /dev/ -t tmpfs -o size=131072
	tar xz -f /dev.tar.gz
	echo 7 >/proc/sys/kernel/printk
	read rootMount </etc/version
	[ "${rootMount}" = "main" ] &&
		currentImage="main" ||
		currentImage="recovery"
	get_pdev partition overlay_1
	if [ ${#partition} -ne 0 -a "$currentImage" = 'main' ]; then
		blkdev=/dev/mtdblock${partition#mtd}
		mkdir -p /tmp/new_root
		echo "Mounting $blkdev (JFFS2) for overlay..."
		if [ -x /usr/sbin/flash_eraseall ]; then
			echo "Memory NAND..."
			mount -t jffs2 $blkdev /overlay
			if [ $? -ne 0 ]; then
				flash_eraseall -j /dev/$partition
				printf "\xde\xad\xc0\xde" | nandwrite /dev/$partition
				echo "Remounting $blkdev (JFFS2) for overlay (NAND) after erase all partition ..."
				mount -t jffs2 $blkdev /overlay
			fi
		else
			echo "Memory NOR..."
			magic=$(hexdump -n 2 -ve '/1 "%02x"' /dev/$partition)
			if [ "$magic" != "1985" ]; then
				printf "\xde\xad\xc0\xde" | mtd write - /dev/$partition
				echo "Write end marker in order to erase partition blocks (NOR)..."
			fi
			mount -t jffs2 $blkdev /overlay
		fi
		if [ "$?" != 0 ]; then
			echo "Erasing overlay partition (/dev/$partition)"
			mtd erase $partition
			mount -t jffs2 $blkdev /overlay
		fi
		echo "Mounting overlay using mini_fo ..."
		mount -t mini_fo -o base=/,sto=/overlay / /tmp/new_root
		mkdir -p /tmp/new_root/old_root
		echo "pivot_root ..."
		pivot_root /tmp/new_root /tmp/new_root/old_root
		mount proc /proc -t proc
		mount tmpfs /tmp -t tmpfs -o size=$size,nosuid,nodev,mode=1777
		mount tmpfs /dev/ -t tmpfs -o size=131072
		tar xz -f /dev.tar.gz
		umount /old_root/tmp
		umount /old_root/proc
	fi
	. /etc/ah/helper_svc.sh
	help_svc_init
	echo "Restore passwd ...."
	cp /etc/passwd.orig /tmp/passwd
	echo "Restore group ...."
	cp /etc/group.orig /tmp/group
	chmod 0600 /tmp/passwd /tmp/group
	echo "mount virtual fs..."
	mount -t usbfs none /proc/bus/usb && ln -s /proc/bus /dev/bus
	mount -t devpts none /dev/pts
	mount tmpfs /mnt -t tmpfs -o size=65536
	mount sysfs /sys -t sysfs
	[ -f /proc/mounts ] || /sbin/mount_root
	[ -f /proc/jffs2_bbc ] && echo "S" >/proc/jffs2_bbc
	[ -f /proc/net/vlan/config ] && vconfig set_name_type DEV_PLUS_VID_NO_PAD
	get_pdev osgipart osgi_cache
	if [ -n "$osgipart" ]; then
		osgiblk="/dev/${osgipart/mtd/mtdblock}"
		mkdir -p /osgi/cache/
		echo "Mounting OSGi cache partition $osgiblk on /osgi/cache"
		mount -t jffs2 $osgiblk /osgi/cache
		if [ "$?" != 0 ]; then
			echo "Erasing osgi-cache partition ($osgiblk)"
			read osgitype </sys/class/mtd/$osgipart/type
			if [ "$osgitype" = "nand" ]; then
				flash_eraseall -j /dev/$osgipart
				printf "\xde\xad\xc0\xde" | nandwrite /dev/$osgipart
			else
				mtd erase $osgipart
			fi
			mount -t jffs2 $osgiblk /osgi/cache
		fi
	fi
	mkdir -p /tmp/voip /tmp/cupsd/ /var/run /var/log /var/lock /var/state
	cp -rf /etc/cups/* /tmp/cupsd/
	touch /var/log/wtmp /var/log/lastlog /tmp/resolv.conf.auto
	ln -sf /tmp/resolv.conf.auto /tmp/resolv.conf
	grep -q debugfs /proc/filesystems && mount -t debugfs debugfs /sys/kernel/debug
	[ "$FAILSAFE" = "true" ] && touch /tmp/.failsafe
	killall -q hotplug2
	[ -x /sbin/hotplug2 ] && /sbin/hotplug2 --override --persistent \
		--set-worker /lib/hotplug2/worker_fork.so \
		--set-rules-file /etc/hotplug2.rules \
		--max-children 1 >/dev/null 2>&1 &
	[ -x /sbin/udevd ] && /sbin/udevd --daemon
	[ -e /dev/root ] || {
		rootdev=$(awk 'BEGIN { RS=" "; FS="="; } $1 == "root" { print $2 }' </proc/cmdline)
		[ -n "$rootdev" ] && ln -s "$rootdev" /dev/root
	}
	date -s "201912191109.41"
	echo "UTC" >/tmp/TZ
}
