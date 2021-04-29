#!/bin/sh

set -x -e

cp -f ${CATTLE_AGENT_EXECUTION_PWD}/k3s /usr/local/bin/k3s
chmod 755 /usr/local/bin/k3s
chown root:root /usr/local/bin/k3s

mkdir -p /var/lib/rancher/k3s

RESTART_STAMP_FILE=/var/lib/rancher/k3s/restart_stamp

if [ -f "${RESTART_STAMP_FILE}" ]; then
    PRIOR_RESTART_STAMP=$(cat "${RESTART_STAMP_FILE}");
fi

if [ "${PRIOR_RESTART_STAMP}" != "${RESTART_STAMP}" ]; then
    FORCE_RESTART=true
else
    FORCE_RESTART=false
fi

env "INSTALL_K3S_FORCE_RESTART=${FORCE_RESTART}" "INSTALL_K3S_SKIP_DOWNLOAD=true" "INSTALL_K3S_SKIP_SELINUX_RPM=true" "INSTALL_K3S_SELINUX_WARN=true" installer.sh $@

echo "${RESTART_STAMP}" > "${RESTART_STAMP_FILE}"