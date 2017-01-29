#!/usr/bin/env bash

set -e

if [ "x${1}" == "x" ]; then
	echo "No VEID given"
	exit 1
fi

if [ "x${2}" == "x" ]; then
	echo "No size in GB given"
	exit 1
fi

VEID="${1}"

[ -f "/etc/vz/rbd.conf" ] || exit 1
. "/etc/vz/rbd.conf"

if ! vzlist "${VEID}" > /dev/null 2> /dev/null; then
	echo "${VEID} is not a valid VEID"
	exit 1
fi

if ! echo -n "${2}" | grep -qE '^[0-9]+$'; then
	echo "${2} is not a valid size in GB"
	exit 1
fi

volsize="$((${2}*1024))"

state=$(vzctl status "${VEID}" 2> /dev/null)

umount=0
case "${state}" in
        "VEID ${VEID} exist mounted running")
		true
        ;;
        "VEID ${VEID} exist mounted down")
		true
        ;;
        "VEID ${VEID} exist unmounted down")
                vzctl mount "${VEID}" || exit 4
		umount=1
        ;;
        *)
                echo "Don't know how to handle VE state: ${state}"
                exit 1
        ;;
esac

rbd --id "${RBDUSER}" -p "${RBDPOOL}" resize --size "${volsize}" "ve-${VEID}"

dfbefore=$(df -h "/vz/root/${VEID}" | fgrep "/vz/root/${VEID}")
resize2fs -p "${RBDPATH}"
dfafter=$(df -h "/vz/root/${VEID}" | fgrep "/vz/root/${VEID}")

if [ "x${umount}" == "x1" ]; then
	vzctl umount "${VEID}"
fi

echo ""
echo "Disk successfully resized"
echo "Pre  resize: ${dfbefore}"
echo "Post resize: ${dfafter}"
