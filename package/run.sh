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

if [ -n "${RESTART_STAMP}" ] && [ "${PRIOR_RESTART_STAMP}" != "${RESTART_STAMP}" ]; then
    FORCE_RESTART=true
else
    FORCE_RESTART=false
fi


# work around for https://github.com/k3s-io/k3s/issues/2306
# depends on journald being available on first boot, so this may not work on all providers (e.g. Digital Ocean)
DELAY=10
while ! env "INSTALL_K3S_FORCE_RESTART=${FORCE_RESTART}" "INSTALL_K3S_SKIP_DOWNLOAD=true" "INSTALL_K3S_SKIP_SELINUX_RPM=true" "INSTALL_K3S_SELINUX_WARN=true" installer.sh $@
do

    # Get the last time the service started using the ExecMainStartTimestamp property
    START=$(systemctl show k3s.service --property=ExecMainStartTimestamp | cut -f2 -d=)

    # if START is n/a or empty, we know we do not have access to the k3s.service and thus are
    # running on a worker node which can not encounter the ETCD error, so we should just exit
    if [ "$START" == "n/a" ] || [ -z "$START" ]; then
        echo "not a K3s server, not attempting error remediation"
        exit 1
    fi

    # Get the logs since the last time the service started and check for the given error
    if journalctl -u k3s.service --since="${START}" | grep -qF "etcdserver: too many learner members in cluster"; then
        # We couldn't register as a learner, keep trying until we can
        sleep "${DELAY}"
    else
        # if we have an error that isn't an etcd learner member error we shouldn't retry
        exit 1
    fi
done


if [ -n "${RESTART_STAMP}" ]; then
    echo "${RESTART_STAMP}" > "${RESTART_STAMP_FILE}"
fi