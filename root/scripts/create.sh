#!/usr/bin/env bash

if [ "x${1:0:1}" != "x-" ]; then
	hostname="${1}"; shift
fi

newhostname=$(echo -n "${hostname}" | tr -d -c '[:alnum:]-_.')

if [ "x${hostname}" != "x${newhostname}" ]; then
	echo "Warning: Your hostname has been filtered from"
	echo "${hostname} to ${newhostname}"
fi

template="debian-8.0-x86_64-minimal"

ctid=$(($(cat /etc/vz/serial)+1))
ipaddr=$(grep -vE '^#' /etc/vz/iplist | while read ip; do vzlist -aHoip | sed -r 's/(.*)/~\1~/' | grep -Fq "~${ip}~" || echo "${ip}"; done | head -n 1)

if [ "x$ipaddr" == "x" ]; then
	echo "NO FREE IPV4 ADDRESS FOUND!"
	exit 1
fi

if ! ssh root@gigafox "zfs list -Honame data/templates/ovz/${template} > /dev/null"; then
	echo "Template ${template} does not exist on gigafox!"
	exit 2
fi

echo -n "${ctid}" > "/etc/vz/serial"

if [ "x${hostname}" == "x" ]; then
	hostname="ve${ctid}"
fi

echo "Creating image from template volume ..."
ssh root@gigafox "zfs send -DLep data/templates/ovz/${template}@latest | zfs recv data/ovz/${ctid}; zfs rename data/ovz/${ctid}@latest data/ovz/${ctid}@init;"
echo "Writing iSCSI share metadata & waiting for device to appear ..."
iscsiserial=$(tr -d -c '[:digit:]' < /dev/urandom | head -c 16)
ssh root@gigafox "cat > /etc/ctl.d/11_target_ovz_${ctid}.conf; cat /etc/ctl.d/* > /etc/ctl.conf; until test -e /dev/zvol/data/ovz/${ctid}; do echo -n .; done; service ctld reload;" <<EOF
target iqn.2015-01.ws.fuslvz:ovz_${ctid} {
	auth-group ovz
	portal-group pg0
	lun 0 {
		serial ${iscsiserial}
		device-id ovz_${ctid}_0
		path /dev/zvol/data/ovz/${ctid}
	}
}
EOF

mkdir -p "/vz/private/${ctid}" "/vz/root/${ctid}"

cat > "/etc/vz/conf/${ctid}.conf" <<EOF
PHYSPAGES="32G"
SWAPPAGES="64G"
DISKSPACE="10G"
CPUUNITS="1000"
NETFILTER="full"
OSTEMPLATE="${template}"
FEATURES="nfs:on"
DEVNODES="net/tun:rw fuse:rw "
VE_LAYOUT="simfs"
DISK_QUOTA="no"
IP_ADDRESS="${ipaddr}"
HOSTNAME="${hostname}"
VE_ROOT="/vz/root/\$VEID"
VE_PRIVATE="/vz/private/\$VEID"
ORIGIN_SAMPLE="default"
EOF

vzctl start "${ctid}"

ssh root@celador "cat > /etc/munin/munin-conf.d/ovz_${ctid}.conf" << EOF
[ve${ctid}-${hostname}.ovz.home]
	address "${ipaddr}"
	use_node_name yes
EOF

echo ""
echo ""
echo "=================================================="
echo "CTID:     ${ctid}"
echo "Hostname: ${hostname}"
echo "IP:       ${ipaddr}"
echo "=================================================="
echo -ne "\e[91m"
echo "Warning: The default volume size of 1GB has been"
echo "left untouched!   Please consider increasing the"
echo "size of the volume using"
echo "~/scripts/resize.sh ${ctid} x"
echo "where x is the desired volume size in GB."
echo -ne "\e[39m"
