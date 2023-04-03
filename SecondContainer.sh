#!/bin/bash -x

IFWAN=`ip route show | grep default | awk '{print $5}'`
IPWAN=`ip -4 addr show $IFWAN | grep inet | tr ' ' '\n' | grep '/[1-9]' | head -1 | cut -d / -f 1`

IFINT=br0
IPINT=192.168.9.251

IPREJECT=192.168.9.253
IPDROP=192.168.9.254

FIRSTCONTAINERIP=192.168.9.1
SECONDTCONTAINERIP=192.168.9.2
######################################
# Strictly no IPV6
######################################

ip6tables -F
ip6tables -t nat -F
ip6tables -t mangle -F
ip6tables -X

ip6tables -P INPUT DROP
ip6tables -P OUTPUT DROP
ip6tables -P FORWARD DROP

ip6tables -I INPUT -j DROP
ip6tables -P INPUT DROP
ip6tables -I OUTPUT -j DROP
ip6tables -P OUTPUT DROP
ip6tables -I FORWARD -j DROP
ip6tables -P FORWARD DROP

# Disable routing.for now
echo 0 > /proc/sys/net/ipv6/conf/default/forwarding

######################################
# Reset IPV4
######################################
# delete all existing rules.
#
iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -X

###################################### 
# Rules
######################################

####### BASICS ##########################################################
### Establich some Reject and Drop Rules for -t nat
iptables -A FORWARD -d $IPREJECT -j REJECT
iptables -A INPUT -d $IPREJECT -j REJECT
iptables -A FORWARD -d $IPDROP -j DROP
iptables -A INPUT -d $IPDROP -j DROP

### Always accept loopback traffic, but only on 127.0.0.1
iptables -A INPUT -i lo -s 127.0.0.1 -d 127.0.0.1 -j ACCEPT
iptables -A OUTPUT -o lo -s 127.0.0.1 -d 127.0.0.1 -j ACCEPT
iptables -A INPUT -i lo -s 127.0.0.0/8 -d 127.0.0.0/8 -j DROP
iptables -A OUTPUT -o lo -s 127.0.0.0/8 -d 127.0.0.0/8 -j DROP

### Accept being ping'ed
iptables -A INPUT -i $IFWAN -p icmp --icmp-type 8 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -o $IFWAN -p icmp -m state --state ESTABLISHED,RELATED -j ACCEPT

### Accept all outgoing traffic from main machine
iptables -A OUTPUT -o $IFWAN -p tcp -j ACCEPT
iptables -A OUTPUT -o $IFWAN -p udp -j ACCEPT
iptables -A OUTPUT -o $IFWAN -p icmp -j ACCEPT

### Accept all incoming traffic to main machine if it belongs to existing connections
iptables -A INPUT -i $IFWAN -p tcp -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A INPUT -i $IFWAN -p udp -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A INPUT -i $IFWAN -p icmp -m state --state RELATED,ESTABLISHED -j ACCEPT

### If something with 192.168.9.x appears at the main interface -> reject it. It shall never be there
iptables -t nat -A PREROUTING ! -i $IFINT -d 192.168.9.0/24 -j DNAT --to-destination 192.168.9.254


####### INCOMING TRAFFIC TO CONTAINERS ######################################

### Optional: Route Incoming http-Traffic to first container
# vvvvvvvvvvvvvvvvvvvvvvvvvvvvv
iptables -t nat -A PREROUTING -p tcp -i $IFWAN -d $IPWAN --dport 80 -j DNAT --to-destination $FIRSTCONTAINERIP:80
iptables -A FORWARD -p tcp -i $IFWAN -d $FIRSTCONTAINERIP --dport 80 -o $IFINT -j ACCEPT
iptables -A FORWARD -p tcp -o $IFWAN -s $FIRSTCONTAINERIP --sport 80 -i $IFINT -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -t nat -A POSTROUTING -p tcp -o $IFWAN -s $FIRSTCONTAINERIP --sport 80 -j SNAT --to-source $IPWAN:80
# ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
####### INCOMING TRAFFIC TO CONTAINERS ######################################
iptables -t nat -A PREROUTING -p tcp -i $IFWAN -d $IPWAN --dport 81 -j DNAT --to-destination $SECONDTCONTAINERIP:81
iptables -A FORWARD -p tcp -i $IFWAN -d $SECONDTCONTAINERIP --dport 81 -o $IFINT -j ACCEPT
iptables -A FORWARD -p tcp -o $IFWAN -s $SECONDTCONTAINERIP --sport 81 -i $IFINT -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -t nat -A POSTROUTING -p tcp -o $IFWAN -s $SECONDTCONTAINERIP --sport 81 -j SNAT --to-source $IPWAN:81
####### INCOMING TRAFFIC TO MAIN SERVER ######################################



### Accept incoming ssh to main server, but only 4 new connections per second
iptables -A INPUT -i $IFWAN -p tcp -d $IPWAN --dport 22 -m state --state NEW -m recent --name wan_22 --update --seconds 60 --hitcount 4 -j LOG --log-level info --log-prefix wansshIN
iptables -A INPUT -i $IFWAN -p tcp -d $IPWAN --dport 22 -m state --state NEW -m recent --name wan_22 --update --seconds 60 --hitcount 4 -j DROP
iptables -A INPUT -i $IFWAN -p tcp -d $IPWAN --dport 22 -m state --state NEW -m recent --name wan_22 --set 
iptables -A INPUT -i $IFWAN -p tcp -d $IPWAN --dport 22 -m state --state NEW -j LOG --log-level info --log-prefix wansshBLOCK

iptables -A INPUT -i $IFWAN -p tcp -d $IPWAN --dport 22 -j ACCEPT
iptables -A OUTPUT -o $IFWAN -p tcp -s $IPWAN --sport 22 -m state --state RELATED,ESTABLISHED -j ACCEPT

### Incoming VNC; ONLY FOR VLIZEDLAB
iptables -A INPUT -i $IFWAN -p tcp -d $IPWAN --dport 5601 -j ACCEPT
iptables -A OUTPUT -o $IFWAN -p tcp -s $IPWAN --sport 5601 -m state --state RELATED,ESTABLISHED -j ACCEPT


######### TRAFFIC BETWEEN MAIN MACHINE AND CONTAINERS ####################

### Accept Traffic from main machine to first container
iptables -A OUTPUT -o $IFINT -s $IPINT -d $FIRSTCONTAINERIP -j ACCEPT
iptables -A INPUT -i $IFINT -d $IPINT -s $FIRSTCONTAINERIP -m state --state ESTABLISHED,RELATED -j ACCEPT

iptables -A OUTPUT -o $IFINT -s $IPINT -d $SECONDTCONTAINERIP -j ACCEPT
iptables -A INPUT -i $IFINT -d $IPINT -s $SECONDTCONTAINERIP -m state --state ESTABLISHED,RELATED -j ACCEPT



######### OUTGOING TRAFFIC FROM CONTAINERS ###############################

### Let the first container reach out via TCP Port 80 (http) SECONDTCONTAINERIP
iptables -A FORWARD -p tcp -i $IFINT -s $FIRSTCONTAINERIP --dport 80 -o $IFWAN -j ACCEPT
iptables -A FORWARD -p tcp -o $IFINT -d $FIRSTCONTAINERIP --sport 80 -i $IFWAN -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -p tcp -o $IFINT -d $FIRSTCONTAINERIP --dport 80 -i $IFWAN -j REJECT
iptables -t nat -A POSTROUTING -p tcp -s $FIRSTCONTAINERIP --dport 80 -j SNAT --to-source $IPWAN

### Let the first container reach out via TCP Port 443 (https)
iptables -A FORWARD -p tcp -i $IFINT -s $FIRSTCONTAINERIP --dport 443 -o $IFWAN -j ACCEPT
iptables -A FORWARD -p tcp -o $IFINT -d $FIRSTCONTAINERIP --sport 443 -i $IFWAN -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -p tcp -o $IFINT -d $FIRSTCONTAINERIP --dport 443 -i $IFWAN -j REJECT
iptables -t nat -A POSTROUTING -p tcp -s $FIRSTCONTAINERIP --dport 443 -j SNAT --to-source $IPWAN

### Let the first container reach out via UDP Port 53 (DNS)
iptables -A FORWARD -p udp -i $IFINT -s $FIRSTCONTAINERIP --dport 53 -o $IFWAN -j ACCEPT
iptables -A FORWARD -p udp -o $IFINT -d $FIRSTCONTAINERIP --sport 53 -i $IFWAN -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -p udp -o $IFINT -d $FIRSTCONTAINERIP --dport 53 -i $IFWAN -j REJECT
iptables -t nat -A POSTROUTING -p udp -s $FIRSTCONTAINERIP --dport 53 -j SNAT --to-source $IPWAN




############################second

### Let the first container reach out via TCP Port 80 (http) SECONDTCONTAINERIP
iptables -A FORWARD -p tcp -i $IFINT -s $SECONDTCONTAINERIP --dport 81 -o $IFWAN -j ACCEPT
iptables -A FORWARD -p tcp -o $IFINT -d $SECONDTCONTAINERIP --sport 81 -i $IFWAN -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -p tcp -o $IFINT -d $SECONDTCONTAINERIP --dport 81 -i $IFWAN -j REJECT
iptables -t nat -A POSTROUTING -p tcp -s $SECONDTCONTAINERIP --dport 81 -j SNAT --to-source $IPWAN

### Let the first container reach out via TCP Port 443 (https)
iptables -A FORWARD -p tcp -i $IFINT -s $SECONDTCONTAINERIP --dport 443 -o $IFWAN -j ACCEPT
iptables -A FORWARD -p tcp -o $IFINT -d $SECONDTCONTAINERIP --sport 443 -i $IFWAN -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -p tcp -o $IFINT -d $SECONDTCONTAINERIP --dport 443 -i $IFWAN -j REJECT
iptables -t nat -A POSTROUTING -p tcp -s $SECONDTCONTAINERIP --dport 443 -j SNAT --to-source $IPWAN

### Let the first container reach out via UDP Port 53 (DNS)
iptables -A FORWARD -p udp -i $IFINT -s $SECONDTCONTAINERIP --dport 53 -o $IFWAN -j ACCEPT
iptables -A FORWARD -p udp -o $IFINT -d $SECONDTCONTAINERIP --sport 53 -i $IFWAN -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -p udp -o $IFINT -d $SECONDTCONTAINERIP --dport 53 -i $IFWAN -j REJECT
iptables -t nat -A POSTROUTING -p udp -s $SECONDTCONTAINERIP --dport 53 -j SNAT --to-source $IPWAN


#######end SECONDTCONTAINERIP



############ CONCLUSION, BLOCK&REJECT RULES  ###############################

### Reject all other traffic from and to the first container
iptables -A INPUT -i $IFINT -d $IPINT -s $FIRSTCONTAINERIP -j REJECT
iptables -A OUTPUT -o $IFINT -s $IPINT -d $FIRSTCONTAINERIP -j REJECT

iptables -A FORWARD -s $FIRSTCONTAINERIP -j DROP
iptables -A FORWARD -d $FIRSTCONTAINERIP -j DROP







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