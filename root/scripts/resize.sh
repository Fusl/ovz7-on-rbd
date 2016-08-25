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

umount=0
case "${state}" in
        "CTID ${ctid} exist mounted running")
		true
        ;;
        "CTID ${ctid} exist mounted down")
		true
        ;;
        "CTID ${ctid} exist unmounted down")
                vzctl mount "${ctid}" || exit 4
		umount=1
        ;;
        *)
                echo "Don't know how to handle VE state: ${state}"
                exit 1
        ;;
esac

sid=$(iscsiadm -m session | fgrep ":ovz_${ctid} " | awk -F'[\\[\\]]' '{print $2}')

if [ "x${sid}" == "x" ]; then
	echo "Couldn't find session ID for iSCSI device"
	exit 5
fi

ssh root@gigafox "zfs set volsize=${volsize_new} data/ovz/${ctid}; service ctld reload;"
sleep 1

iscsiadm -m session -r "${sid}" -R || exit 6

dfbefore=$(df -h "/vz/root/${ctid}" | fgrep "/vz/root/${ctid}")
resize2fs -p "/dev/disk/by-path/ip-"*"-iscsi-"*":ovz_${ctid}-lun-0"
dfafter=$(df -h "/vz/root/${ctid}" | fgrep "/vz/root/${ctid}")

if [ "x${umount}" == "x1" ]; then
	vzctl umount "${ctid}"
fi

echo ""
echo "Disk successfully resized"
echo "Pre  resize: ${dfbefore}"
echo "Post resize: ${dfafter}"
