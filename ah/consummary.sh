#!/bin/sh
inputfile=$1
awk -v ipAddr1=$2 -v subMask1=$3 -v ipAddr8=$4 -v subMask8=$5 ' 
function ipnet(IPaddr, SubMask) {       
	split(IPaddr, ip, ".");
	split(SubMask, sm, ".");    
	for ( i=1; i<=4; i++ ) {
             if ( sm[i] == 255 ) np[i] = ip[i];
             else if ( sm[i] == 0   ) np[i] = 0;
                  else {  s = 256 - sm[i];
                          h = ip[i] % s;
                          np[i] = ip[i] - h;
                  }
          }
	return(sprintf("%d.%d.%d.%d", np[1], np[2], np[3], np[4]))
}
function isIPAddressInLanIfs(IPaddr) {
	lanIpAddr=ipnet(IPaddr, subMask1)
	if (lanIpAddr == lanIpAddr1) {
		return ("1")
	}
	lanIpAddr=ipnet(IPaddr, subMask8)
	if (lanIpAddr == lanIpAddr8) {
		return ("1")
	}
	return("0")
}
BEGIN {
	lanIpAddr1=ipnet(ipAddr1, subMask1)
	lanIpAddr8=ipnet(ipAddr8, subMask8)
}
{proto=$3;ttl=$5;protonum=$4;if(proto=="tcp") 
			{
			split($7,txsrc,"=");
			split($8,txdst,"=");		
			split($9,txsport,"=");	
			split($10,txdport,"=");
			split($13,tmp,"=");
			 if(tmp[1]!="src")offset=1;
			 else offset=0;
			fieldtmp=offset+13; split($fieldtmp,rxsrc,"=");
			fieldtmp=offset+14; split($fieldtmp,rxdst,"=");	
			fieldtmp=offset+15; split($fieldtmp,rxsport,"=");
			fieldtmp=offset+16; split($fieldtmp,rxdport,"=");
			fieldtmp=offset+17; split($fieldtmp,rxpackets,"=");
			fieldtmp=offset+18; split($fieldtmp,rxbytes,"=");
			split($11,txpackets,"=");
			split($12,txbytes,"=");
			wanstatus=$6;
			} else if (proto=="udp") { 
			 split($6,txsrc,"=");		
			 split($7,txdst,"=");
			 split($8,txsport,"=");	
			 split($9,txdport,"=");
			 split($12,tmp,"=");
			  if (tmp[1]!="src") offset=1;
			  else offset=0;
			 fieldtmp=offset+12; split($fieldtmp,rxsrc,"=");
			 fieldtmp=offset+13; split($fieldtmp,rxdst,"=");	
			 fieldtmp=offset+14; split($fieldtmp,rxsport,"=");
			 fieldtmp=offset+15; split($fieldtmp,rxdport,"=");
			 fieldtmp=offset+16; split($fieldtmp,rxpackets,"=");
			 fieldtmp=offset+17; split($fieldtmp,rxbytes,"=");
			 split($10,txpackets,"=");
			 split($11,txbytes,"=");
			 wanstatus="";
			} else if (proto=="icmp") {
			 split($6,txsrc,"=");
			 split($7,txdst,"=");
			 split($8,txtype,"=");	
			 split($9,txcode,"=");	
			 split($10,txid,"=");
			 split($13,tmp,"=");
			  if (tmp[1]!="src") offset=1;
			  else offset=0;
			 fieldtmp=offset+13; split($fieldtmp,rxsrc,"=");
			 fieldtmp=offset+14; split($fieldtmp,rxdst,"=");	
			 fieldtmp=offset+15; split($fieldtmp,rxtype,"=");
			 fieldtmp=offset+16; split($fieldtmp,rxcode,"=");
			 fieldtmp=offset+17; split($fieldtmp,rxid,"=");
			 fieldtmp=offset+18; split($fieldtmp,rxpackets,"=");
			 fieldtmp=offset+19; split($fieldtmp,rxbytes,"=");
			 split($11,txpackets,"=");
			 split($12,txbytes,"=");
			 wanstatus="";
		      }
		     islanipaddrtxsrc=isIPAddressInLanIfs(txsrc[2])
		     islanipaddrtxdst=isIPAddressInLanIfs(txdst[2])
	             islanipaddrrxsrc=isIPAddressInLanIfs(rxsrc[2]) 
	             islanipaddrrxdst=isIPAddressInLanIfs(rxdst[2])							
                     skip="0"
 	             if (islanipaddrtxsrc=="1" && islanipaddrtxdst=="1") { 
		       skip="1"
	  	     } 
				if (islanipaddrtxsrc!="1" && islanipaddrtxdst!="1" && islanipaddrrxsrc!="1" && islanipaddrrxdst!="1") {
		         skip="1"
	             }
			if (islanipaddrtxsrc=="1") {
			direction="Outgoing";		
				if (txsport[2]!="") lanpeer=txsrc[2]":"txsport[2];
			else lanpeer=txsrc[2];
			if (txdport[2]!="") wanpeer=txdst[2]":"txdport[2];     
			else wanpeer=txdst[2];
			modemip=rxdst[2];
			if (txdport[2]!="") modempeer=rxdst[2]":"rxdport[2];     
			else modempeer=rxdst[2];
		     } else {
			direction="Incoming";
			if (rxsport[2]!="") lanpeer=rxsrc[2]":"rxsport[2];
			else $lanpeer=rxsrc[2];
			if (txsport[2]!="") wanpeer=txsrc[2]":"txsport[2];
			else wanpeer=txsrc[2];
			modemip=txdst[2];
			if (txdport[2]!="") modempeer=txdst[2]":"txdport[2];
			else modempeer=txdst[2];
		    }
			if (txsrc[2]!=rxdst[2] || txdst[2]!=rxsrc[2]) {
				routingmode="NAT";
			} else {
				routingmode="Normal Routing";
			}
			packets=txpackets[2]"/"rxpackets[2];
			bytes=txbytes[2]"/"rxbytes[2];
			if (skip=="0")
			{
				print (proto","protonum","ttl","connstatus","packets","bytes","direction","lanpeer","wanpeer","modempeer","routingmode","wanstatus","rxsrc[2]","rxsport[2]","rxdst[2]","rxdport[2]","txsrc[2]","txsport[2]","txdst[2]","txdport[2]","rxpackets[2]","rxbytes[2]","txpackets[2]","txbytes[2]","rxcode[2]","rxid[2]","rxtype[2]","modemip","wanif","wanip)
			}
}' $inputfile

line_count=0
count_sw=0
count_hw=0
swTotHits="0"
hwTotHits="0"

if [ -f /tmp/nflist ]; then
	if [ -s /tmp/nflist ]; then
		cat /tmp/nflist | while IFS=" " read flowObject idle swhit swTotHits totalBytes CMFtpl hwTotHits V4Conntrack V6Conntrack L1Info Prot sourceIpAddress destinIpAddress vlanID tag IqPrio SkbMark; do
			if [ $line_count -gt 1 ]; then
				if [ "${swTotHits%%":"}" != "0" ]; then
					count_sw=$(expr $count_sw + 1)
					echo "$count_sw" >/tmp/nflist_sw_acc
				fi
				if [ "$hwTotHits" != "0" ]; then
					count_hw=$(expr $count_hw + 1)
					echo "$count_hw" >/tmp/nflist_hw_acc
				fi
			fi
			line_count=$(expr $line_count + 1)
		done

		count_sw=$(cat /tmp/nflist_sw_acc)
		count_hw=$(cat /tmp/nflist_hw_acc)
		count_sw=$(expr $count_sw - 1)
		count_hw=$(expr $count_hw - 1)
		echo "$count_sw" >/tmp/nflist_sw_acc
		echo "$count_hw" >/tmp/nflist_hw_acc
	fi
fi
