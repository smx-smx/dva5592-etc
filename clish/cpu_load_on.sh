#!/bin/sh
echo ""
while true; do
	sleep $1
	read -r _ sample1 _ </proc/stat
	sleep 1
	read -r _ sample2 _ </proc/stat
	sample2=$((sample2 - sample1))
	if [ $sample2 -le 100 ]; then
		echo "cpu load = $sample2 %"
	else
		echo "cpu load = 100 %"
	fi
done
