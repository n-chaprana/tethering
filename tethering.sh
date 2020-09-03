#!/bin/bash

TETHER_IP_ADDR1="192.168.43.1"
TETHER_IP_ADDR2="192.168.44.2"

enable_tethering()
{
	if [ -z "$1" ]; then
		echo "Kindly enter backend_ifname "
		print_usage
		exit 1
	fi
	
	if [ -z "$2" ]; then
		echo "Kindly enter frontend_ifname "
		print_usage
		exit 1
	fi
	
	disable_tethering ${1} ${2}

	cp /usr/bin/hostapd /usr/bin/hostapd_${2}
	chsmack -a "_" /usr/bin/hostapd_${2}
	cp /usr/bin/dnsmasq /usr/bin/dnsmasq_${2}
	chsmack -a "_" /usr/bin/dnsmasq_${2}

	if [[ "$2" == "wlan0" ]]; then
		ifconfig ${2} ${TETHER_IP_ADDR1} up
		ip route replace default via ${TETHER_IP_ADDR1} dev ${2} scope global table 252
	else
		ifconfig ${2} ${TETHER_IP_ADDR2} up
		ip route replace default via ${TETHER_IP_ADDR2} dev ${2} scope global table 252
	fi

	start_hostapd_and_dnsmasq ${2}
	add_forwarding_rules ${1} ${2}
}

disable_tethering()
{
	if [ -z "$1" ]; then
		echo "Kindly enter backend_ifname "
		print_usage
		exit 1
	fi
	
	if [ -z "$2" ]; then
		echo "Kindly enter frontend_ifname "
		print_usage
		exit 1
	fi
	
	remove_forwarding_rules ${1} ${2}
	stop_hostapd_and_dnsmasq ${2}

	rm /usr/bin/hostapd_${2}
	rm /usr/bin/dnsmasq_${2}

	if [[ "$2" == "wlan0" ]]; then
		ip route del default via ${TETHER_IP_ADDR1} dev ${2} scope global table 252
	else
		ip route del default via ${TETHER_IP_ADDR2} dev ${2} scope global table 252
	fi
	ifconfig ${2} down

}

start_hostapd_and_dnsmasq()
{
	mkdir -p /run/network/log

cat << EOF > /run/network/hostapd_${1}.conf
interface=${1}
driver=nl80211
ctrl_interface=/run/network/hostapd_${1}
ssid=SoftAP_${1}
channel=6
ignore_broadcast_ssid=0
hw_mode=g
max_num_sta=10
ieee80211n=1
EOF

cat << EOF > /tmp/dnsmasq_${1}.conf
dhcp-range=192.168.43.3,192.168.43.150,255.255.255.0
dhcp-range=192.168.44.3,192.168.44.150,255.255.255.0
enable-dbus
group=system
user=system
dhcp-option=6,0.0.0.0
EOF
	hostapd_${1} -e /opt/var/lib/misc/hostapd_${1}.bin /run/network/hostapd_${1}.conf -f /run/network/log/hostapd_${1}.log -ddd -B
	#dnsmasq_${1} -p 0 -i ${1} -C /tmp/dnsmasq_${1}.conf
	dnsmasq_${1} -p 0 -C /tmp/dnsmasq_${1}.conf
}

stop_hostapd_and_dnsmasq()
{
	pkill hostapd_${1}
	pkill dnsmasq_${1}
}

remove_forwarding_rules()
{
	IP=$(/sbin/ip -o -4 addr list ${1} | awk '{print $4}' | cut -d/ -f1)
	GATEWAY=$(ip route show 0.0.0.0/0 dev ${1} | cut -d\  -f3)

#	echo "${1}:"
#	echo "       ip addr [$IP]"
#	echo "       gw addr [$GATEWAY]"

	iptables -t nat -D POSTROUTING -o ${1} -j MASQUERADE
	iptables -D FORWARD -i ${1} -o ${2} -m state --state RELATED,ESTABLISHED -j ACCEPT
	iptables -D FORWARD -i ${2} -o ${1} -j ACCEPT

	ip route del default via ${GATEWAY} dev ${1} scope global table 252

	ip route del 192.168.0.0/24 table 252 dev ${2}
	ip rule del iif ${2} lookup 252
	route del -net 224.0.0.0 netmask 224.0.0.0 ${2}

#	echo 0 > /proc/sys/net/ipv4/ip_forward
}

add_forwarding_rules()
{
	IP=$(/sbin/ip -o -4 addr list ${1} | awk '{print $4}' | cut -d/ -f1)
	GATEWAY=$(ip route show 0.0.0.0/0 dev ${1} | cut -d\  -f3)

#	echo "${1}:"
#	echo "       ip addr [$IP]"
#	echo "       gw addr [$GATEWAY]"

	echo 1 > /proc/sys/net/ipv4/ip_forward

	iptables -t nat -A POSTROUTING -o ${1} -j MASQUERADE
	iptables -A FORWARD -i ${1} -o ${2} -m state --state RELATED,ESTABLISHED -j ACCEPT
	iptables -A FORWARD -i ${2} -o ${1} -j ACCEPT

	ip route replace default via ${GATEWAY} dev ${1} scope global table 252

	ip route add 192.168.0.0/24 table 252 dev ${2}
	ip rule add iif ${2} lookup 252
	route add -net 224.0.0.0 netmask 224.0.0.0 ${2}
}

print_usage()
{
	echo "Usage:"
	echo "        tethering.sh <enable|disable> <backend_ifname> <frontend_ifname>"
}

case $1 in
"enable")
echo "Enabling tethering backend ${2}, frontend ${3}"
enable_tethering ${2} ${3}
;;
"disable")
echo "Disabling tethering backend ${2}, frontend ${3}"
disable_tethering ${2} ${3}
;;
*)
print_usage
exit 1
;;
esac
exit 0
