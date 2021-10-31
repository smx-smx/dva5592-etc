#! /bin/sh
st=$1
ll=${#st}
let lq=$ll-2
c=0
out=""
while [ $c -le $lq ]; do
	a=${st:$c:2}
	let c=c+2
	out=$out$(echo "0x$a" | awk '{printf "%c",$1}')
done
echo "$out"
