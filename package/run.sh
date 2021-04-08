#!/bin/sh

set -x -e

cp -f ${CATTLE_AGENT_EXECUTION_PWD}/k3s /usr/local/bin/k3s
chmod 755 /usr/local/bin/k3s
chown root:root /usr/local/bin/k3s

env "INSTALL_K3S_SKIP_DOWNLOAD=true" "INSTALL_K3S_SKIP_SELINUX_RPM=true" "INSTALL_K3S_SELINUX_WARN=true" installer.sh $@