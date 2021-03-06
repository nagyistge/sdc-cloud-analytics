#!/usr/bin/bash
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#

#
# Copyright (c) 2014, Joyent, Inc.
#

PATH=/usr/bin:/usr/sbin
export PATH

if [[ $# != 2 ]]; then
  echo "Usage: $0 <zone_name> <target_directory>"
  exit 1
fi

ZONE=$1
TARGET_DIR=$2
ROLE="ca"

# Just in case, create the backup directory:
if [[ ! -e "${TARGET_DIR}" ]]; then
  mkdir -p ${TARGET_DIR}
fi

DATA_DATASET=$(zfs list -H -o name|grep "${ZONE}/data$")
STAMP=$(date +'%F-%H-%M-%S-%Z')

BACKUP_VERSION="cadata-${STAMP}"

# We cannot backup if cannot find data dataset:
if [[ -z $DATA_DATASET ]]; then
  echo "FATAL: Cannot find '${ROLE}' data dataset"
  exit 103
fi

# Create data dataset backup
echo "==> Creating snapshot of '${ZONE}/data' dataset"
zfs snapshot zones/${ZONE}/data@${BACKUP_VERSION} 2>&1
if [[ $? -gt 0 ]]; then
    echo "FATAL: Unable to snapshot data dataset"
    exit 106
fi

# Create backup directory for the zone stuff:
echo "==> Creating backup directory '${TARGET_DIR}/${ROLE}'"
mkdir -p "${TARGET_DIR}/${ROLE}"

# Send the dataset snapshots:

echo "==> Saving data dataset"
zfs send "zones/${ZONE}/data@${BACKUP_VERSION}" \
    > "${TARGET_DIR}/${ROLE}/ca-data.zfs" 2>&1
if [[ $? -gt 0 ]]; then
    echo "Unable to zfs send data dataset"
    exit 108
fi

echo "==> Removing temporary snapshot of '${ZONE}'"
/usr/sbin/zfs destroy "zones/${ZONE}/data@${BACKUP_VERSION}"

exit 0
