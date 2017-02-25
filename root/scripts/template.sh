#!/usr/bin/env bash

set -e

[ -f "/etc/vz/rbd.conf" ] || exit 1
. "/etc/vz/rbd.conf"

templatename="${1}"

VEID=$(uuidgen -r | sed 's/^........-....-4...-....-/00000000-0000-4000-0000-/')

prlctl create "vetmpl-${templatename}" --ostemplate "${templatename}" --vmtype=ct --uuid="${VEID}"

prlctl mount "${VEID}"

rbd --id "${RBDUSER}" -p "${RBDPOOL}" info "vetmpl-${templatename}" 1> /dev/null 2> /dev/null || rbd --id "${RBDUSER}" -p "${RBDPOOL}" create --size $((1*1024)) --image-format 2 --image-shared "vetmpl-${templatename}"

VE_ROOT=$(vzlist -Horoot "${VEID}")

TE_ROOT=$(mktemp -d)

rbd --id "${RBDUSER}" -p "${RBDPOOL}" map "vetmpl-${templatename}"

mkfs.ext4 -F "/dev/rbd/${RBDPOOL}/vetmpl-${templatename}"

mount "/dev/rbd/${RBDPOOL}/vetmpl-${templatename}" "${TE_ROOT}"

rsync -aHAX --numeric-ids --delete "${VE_ROOT}/" "${TE_ROOT}/"

mkdir -p "${TE_ROOT}/root/.ssh/"
cat > "${TE_ROOT}/root/.ssh/authorized_keys" << EOF
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFSBkWq9w1UOT4m90XtI0P1o/NUpj8VhQPSezUsIQSgx fusl@linux-xuzz.site
EOF

umount "${TE_ROOT}"

sync

rbd unmap "/dev/rbd/${RBDPOOL}/vetmpl-${templatename}"

prlctl umount "${VEID}"

prlctl destroy "${VEID}"

echo "Template ${templatename} has been successfully created:"

rbd --id "${RBDUSER}" -p "${RBDPOOL}" info "vetmpl-${templatename}"
