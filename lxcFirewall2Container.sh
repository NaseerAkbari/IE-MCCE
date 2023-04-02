#!/bin/bash -x

SECONDTCONTAINERIP=192.168.9.2

### Optional: Route Incoming http-Traffic to SECOND container
# vvvvvvvvvvvvvvvvvvvvvvvvvvvvv
iptables -t nat -A PREROUTING -p tcp -i $IFWAN -d $IPWAN --dport 443 -j DNAT --to-destination $SECONDTCONTAINERIP:443
iptables -A FORWARD -p tcp -i $IFWAN -d $SECONDTCONTAINERIP --dport 443 -o $IFINT -j ACCEPT
iptables -A FORWARD -p tcp -o $IFWAN -s $SECONDTCONTAINERIP --sport 443 -i $IFINT -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -t nat -A POSTROUTING -p tcp -o $IFWAN -s $SECONDTCONTAINERIP --sport 443 -j SNAT --to-source $IPWAN:443
# ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^


######### TRAFFIC BETWEEN MAIN MACHINE AND CONTAINERS ####################

### Accept Traffic from main machine to SECOND container
iptables -A OUTPUT -o $IFINT -s $IPINT -d $SECONDTCONTAINERIP -j ACCEPT
iptables -A INPUT -i $IFINT -d $IPINT -s $SECONDTCONTAINERIP -m state --state ESTABLISHED,RELATED -j ACCEPT


######### OUTGOING TRAFFIC FROM CONTAINERS ###############################

### Let the SECONDcontainer reach out via TCP Port 80 (http)
iptables -A FORWARD -p tcp -i $IFINT -s $SECONDTCONTAINERIP --dport 80 -o $IFWAN -j ACCEPT
iptables -A FORWARD -p tcp -o $IFINT -d $SECONDTCONTAINERIP --sport 80 -i $IFWAN -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -p tcp -o $IFINT -d $SECONDTCONTAINERIP --dport 80 -i $IFWAN -j REJECT
iptables -t nat -A POSTROUTING -p tcp -s $SECONDTCONTAINERIP --dport 80 -j SNAT --to-source $IPWAN

### Let the SECOND container reach out via TCP Port 443 (https)
iptables -A FORWARD -p tcp -i $IFINT -s $SECONDTCONTAINERIP --dport 443 -o $IFWAN -j ACCEPT
iptables -A FORWARD -p tcp -o $IFINT -d $SECONDTCONTAINERIP --sport 443 -i $IFWAN -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -p tcp -o $IFINT -d $SECONDTCONTAINERIP --dport 443 -i $IFWAN -j REJECT
iptables -t nat -A POSTROUTING -p tcp -s $SECONDTCONTAINERIP --dport 443 -j SNAT --to-source $IPWAN

### Let the SECOND container reach out via UDP Port 53 (DNS)
iptables -A FORWARD -p udp -i $IFINT -s $SECONDTCONTAINERIP --dport 53 -o $IFWAN -j ACCEPT
iptables -A FORWARD -p udp -o $IFINT -d $SECONDTCONTAINERIP --sport 53 -i $IFWAN -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -p udp -o $IFINT -d $SECONDTCONTAINERIP --dport 53 -i $IFWAN -j REJECT
iptables -t nat -A POSTROUTING -p udp -s $SECONDTCONTAINERIP --dport 53 -j SNAT --to-source $IPWAN


############ CONCLUSION, BLOCK&REJECT RULES  ###############################

### Reject all other traffic from and to the SECOND container
iptables -A INPUT -i $IFINT -d $IPINT -s $SECONDTCONTAINERIP -j REJECT
iptables -A OUTPUT -o $IFINT -s $IPINT -d $SECONDTCONTAINERIP -j REJECT

iptables -A FORWARD -s $SECONDTCONTAINERIP -j DROP
iptables -A FORWARD -d $SECONDTCONTAINERIP -j DROP

# iptables -A INPUT -j LOG --log-prefix DROP
# iptables -A OUTPUT -j LOG --log-prefix DROP
# iptables -A FORWARD -j LOG --log-prefix DROP

### Drop everything else
iptables -A INPUT -j DROP
iptables -A OUTPUT -j DROP
iptables -A FORWARD -j DROP

echo 1 > /proc/sys/net/ipv4/ip_forward