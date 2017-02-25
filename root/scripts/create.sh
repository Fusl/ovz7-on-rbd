#!/usr/bin/env bash

set -e

[ -f "/etc/vz/rbd.conf" ] || exit 1
. "/etc/vz/rbd.conf"

hostname="${1}"; shift

newhostname=$(echo -n "${hostname}" | tr -d -c '[:alnum:]-_.')

if [ "x${hostname}" != "x${newhostname}" ]; then
	echo "Warning: Your hostname has been filtered from"
	echo "${hostname} to ${newhostname}"
fi

template="${1}"
if [ "x${template}" == "x" ]; then
	template="debian-8.0-x86_64-minimal"
fi

distribution=$(echo -n "${template}" | cut -d- -f1)

veid=$(uuidgen -r)
ipaddr=$(grep -vE '^#' /etc/vz/iplist | shuf | while read ip; do vzlist -aHoip | sed -r 's/(.*)/~\1~/' | grep -Fq "~${ip}~" || echo "${ip}"; done | head -n 1)

if [ "x$ipaddr" == "x" ]; then
	echo "NO FREE IPV4 ADDRESS FOUND!"
	exit 1
fi

if ! rbd --id "${RBDUSER}" -p "${RBDPOOL}" info "vetmpl-${template}" > /dev/null 2> /dev/null; then
	echo "Template ${template} does not exist!"
	exit 2
fi

if [ "x${hostname}" == "x" ]; then
	hostname="ve$(tr -d -c '[:lower:][:digit:]' < /dev/urandom | head -c 8)"
fi

echo "Creating image from template volume ..."
rbd --id "${RBDUSER}" -p "${RBDPOOL}" cp "${RBDPOOL}/vetmpl-${template}" "${RBDPOOL}/ve-${veid}"

mkdir -p "/vz/private/${veid}" "/vz/root/${veid}"

cat > "/etc/vz/conf/${veid}.conf" <<EOF
PHYSPAGES="32G"
SWAPPAGES="64G"
DISKSPACE="1G"
CPUUNITS="1000"
NETFILTER="full"
OSTEMPLATE=".${template}"
FEATURES="nfs:on"
DEVNODES="net/tun:rw fuse:rw "
VE_LAYOUT="simfs"
VEFSTYPE="simfs"
DISK_QUOTA="no"
IP_ADDRESS="${ipaddr}/255.255.255.255"
HOSTNAME="${hostname}"
NAME="${hostname}"
VE_ROOT="/vz/root/\$VEID"
VE_PRIVATE="/vz/private/\$VEID"
TECHNOLOGIES="x86_64 nptl"
DISTRIBUTION="${distribution}"
ONBOOT="yes"
VEID="${veid}"
UUID="${veid}"
EOF

vzctl start "${veid}"

echo ""
echo ""
echo "=================================================="
echo "VEID:     ${veid}"
echo "Hostname: ${hostname}"
echo "IP:       ${ipaddr}"
echo "=================================================="
echo -ne "\e[91m"
echo "~/scripts/resize.sh ${veid} size-in-gb"
echo -ne "\e[39m"
