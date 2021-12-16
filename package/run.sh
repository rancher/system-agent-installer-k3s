#!/bin/sh

set -x -e

SA_INSTALL_PREFIX="/usr/local"

# check_target_mountpoint return success if the target directory is on a dedicated mount point
check_target_mountpoint() {
    mountpoint -q "${SA_INSTALL_PREFIX}"
}

# check_target_ro returns success if the target directory is read-only
check_target_ro() {
    touch "${SA_INSTALL_PREFIX}"/.k3s-ro-test && rm -rf "${SA_INSTALL_PREFIX}"/.k3s-ro-test
    test $? -ne 0
}

if check_target_mountpoint || check_target_ro; then
    echo "${SA_INSTALL_PREFIX} is ro or a mount point"
    SA_INSTALL_PREFIX="/opt"
fi

cp -f ${CATTLE_AGENT_EXECUTION_PWD}/k3s ${SA_INSTALL_PREFIX}/bin/k3s
chmod 755 ${SA_INSTALL_PREFIX}/bin/k3s
chown root:root ${SA_INSTALL_PREFIX}/bin/k3s

mkdir -p /var/lib/rancher/k3s

RESTART_STAMP_FILE=/var/lib/rancher/k3s/restart_stamp

if [ -f "${RESTART_STAMP_FILE}" ]; then
    PRIOR_RESTART_STAMP=$(cat "${RESTART_STAMP_FILE}");
fi

if [ -n "${RESTART_STAMP}" ] && [ "${PRIOR_RESTART_STAMP}" != "${RESTART_STAMP}" ]; then
    FORCE_RESTART=true
else
    FORCE_RESTART=false
fi

env "INSTALL_K3S_FORCE_RESTART=${FORCE_RESTART}" "INSTALL_K3S_SKIP_DOWNLOAD=true" "INSTALL_K3S_SKIP_SELINUX_RPM=true" "INSTALL_K3S_SELINUX_WARN=true" installer.sh $@

if [ -n "${RESTART_STAMP}" ]; then
    echo "${RESTART_STAMP}" > "${RESTART_STAMP_FILE}"
fi