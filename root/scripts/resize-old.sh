#!/usr/bin/env bash

if [ "x${1}" == "x" ]; then
	echo "No CTID given"
	exit 1
fi

if [ "x${2}" == "x" ]; then
	echo "No size in GB given"
	exit 1
fi

ctid="${1}"

if ! vzlist "${ctid}" > /dev/null 2> /dev/null; then
	echo "${ctid} is not a valid CTID"
	exit 1
fi

if ! echo -n "${2}" | grep -qE '^[0-9]+$'; then
	echo "${2} is not a valid size in GB"
	exit 1
fi

volsize_new="$((${2}*1024*1024*1024))"

volsize_cur=$(ssh root@gigafox "zfs get -Hpovalue volsize data/ovz/${ctid}")

if [ "${volsize_new}" == "${volsize_cur}" ]; then
	echo "Volume is already ${volsize_cur} bytes large, not resizing"
	echo "Warning: You're putting your data at risk if you try to forcefully resize this volume to a smaller size!"
	exit 2
fi

if [ "${volsize_new}" -lt "${volsize_cur}" ]; then
	echo "Volume is larger (${volsize_cur} bytes) than size given for resizing (${volsize_new} bytes), not resizing"
	echo "Warning: You're putting your data at risk if you try to forcefully resize this volume to a smaller size!"
	exit 3
fi

state=$(vzctl status "${ctid}" 2> /dev/null)

startafterresize=0
if [ "x${state}" != "xCTID ${ctid} exist unmounted down" ]; then
	echo "Container needs to be stopped & unmounted"
	exit 4
fi
vzctl mount "${ctid}" || exit 5

sid=$(iscsiadm -m session | fgrep ":ovz_${ctid} " | awk -F'[\\[\\]]' '{print $2}')

if [ "x${sid}" == "x" ]; then
	echo "Couldn't find session ID for iSCSI device"
	vzctl umount "${ctid}" || exit 6
	exit 5
fi

VE_ROOT="/vz/root/${ctid}"

findmnt -lnR -o target "${VE_ROOT}" | tail -n +2 | tac | xargs --no-run-if-empty umount
umount -v "${VE_ROOT}" && mount -v -o ro -t tmpfs tmpfs "${VE_ROOT}"

ssh root@gigafox "zfs set volsize=${volsize_new} data/ovz/${ctid}; service ctld reload;"
sleep 1

iscsiadm -m session -r "${sid}" -R || exit 6

e2fsck -f "/dev/disk/by-path/ip-"*"-iscsi-"*":ovz_${ctid}-lun-0"
resize2fs -p "/dev/disk/by-path/ip-"*"-iscsi-"*":ovz_${ctid}-lun-0"

vzctl umount "${ctid}"

echo ""
echo "Disk successfully resized"
