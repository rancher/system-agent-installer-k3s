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
    if ! systemctl cat k3s.service > /dev/null && echo $?; then
        # if k3s.service can not be found then we are not a server node and thus will never encounter the 'too many learners' error, so we should just exit
        echo "not a K3s server, not attempting error remediation"
        exit 1
    fi
    # We need to get the right systemd service based off of the role we have, $INSTALL_K3S_EXEC will be set if we are a worker only node, in which case the systemd service is k3s-agent.service
    journalctl -u k3s.service > k3s-service.txt
    # Only use the logs for the latest restart of k3s, otherwise errors encountered after an ETCD join error will not be reported properly.
    LAST_START_LINE=$(cat k3s-service.txt | grep "Starting k3s v1." -n  | cut -d: -f1 | tail -1)
    if [[ "$LAST_START_LINE" -gt 0 ]]; then
        LAST_LOGS=$(cat k3s-service.txt | sed -n "$((LAST_START_LINE))"',$p')
        else
        LAST_LOGS=$(cat k3s-service.txt)
    fi
    if ! echo "${LAST_LOGS}" | grep "ETCD join failed: etcdserver: too many learner members in cluster" -q && echo $?; then
        exit 1
        else
        # We couldn't register as a learner, keep trying until we can
        sleep "${DELAY}"
    fi
done


if [ -n "${RESTART_STAMP}" ]; then
    echo "${RESTART_STAMP}" > "${RESTART_STAMP_FILE}"
fi