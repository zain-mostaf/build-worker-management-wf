#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/linux-master-deployment-env.json"

check_jq() { command -v jq >/dev/null 2>&1 || { command -v dnf >/dev/null 2>&1 && dnf install -y jq || yum install -y jq; }; }
value() { jq -r --arg key "$1" '.[$key] // empty' "$ENV_FILE"; }
load_variables() {
    check_jq
    [[ -r "$ENV_FILE" ]] || { echo "ERROR: Missing JSON file: $ENV_FILE" >&2; return 1; }
    jq empty "$ENV_FILE" >/dev/null || { echo "ERROR: Invalid JSON: $ENV_FILE" >&2; return 1; }
    EGO_TOP="$(value EGO_TOP)"; EGO_TOP="${EGO_TOP:-/opt/ibm/spectrumcomputing}"
    CLUSTER_ADMIN="$(value CLUSTER_ADMIN)"; CLUSTER_ADMIN="${CLUSTER_ADMIN:-egoadmin}"
    SHARED_EGO_TOP="$(value SHARED_EGO_TOP)"
    NFS_STORAGE_PATH="$(value nfs_storage_path)"
    EGO_PRIMARY_HOST="$(value ego_primary_host)"
    CLUSTER_DOMAIN="$(value cluster_domain)"
    DNS_SERVER="$(value dns_server_ips)"; DNS_SERVER="${DNS_SERVER:-161.26.0.10}"
    SYMPHONY_SOAM_CERTIFICATE="$(value symphony_soam_certificate)"
}

configure_network() {
    local connection="System eth0"
    systemctl restart NetworkManager
    nmcli -t -f NAME connection show "$connection" >/dev/null 2>&1 || { echo "ERROR: Missing connection $connection" >&2; return 1; }
    nmcli connection modify "$connection" ipv4.dns "$DNS_SERVER" ipv4.ignore-auto-dns yes ipv4.dns-options single-request-reopen
    [[ -z "$CLUSTER_DOMAIN" ]] || nmcli connection modify "$connection" ipv4.dns-search "$CLUSTER_DOMAIN"
    nmcli connection modify "$connection" 802-3-ethernet.mtu 9000
    nmcli connection up "$connection" >/dev/null 2>&1
    if grep -q '^PEERDNS=' /etc/sysconfig/network-scripts/ifcfg-eth0 2>/dev/null; then
        sed -i 's/^PEERDNS=.*/PEERDNS=no/' /etc/sysconfig/network-scripts/ifcfg-eth0
    else
        printf '%s\n' 'PEERDNS=no' >> /etc/sysconfig/network-scripts/ifcfg-eth0
    fi
    while IFS= read -r route; do
        [[ -z "$route" ]] && continue
        local connection_name gateway priority table cidr
        connection_name="$(jq -r '.conn_name' <<<"$route")"; gateway="$(jq -r '.gateway' <<<"$route")"
        priority="$(jq -r '.priority' <<<"$route")"; table="$(jq -r '.table' <<<"$route")"; cidr="$(jq -r '.cidr' <<<"$route")"
        nmcli connection modify "$connection_name" +ipv4.routes "0.0.0.0/0 $gateway table=$table"
        nmcli connection modify "$connection_name" +ipv4.routing-rules "priority $priority from $cidr table $table, priority $priority to $cidr table $table"
    done < <(jq -c '.additional_routes[]?' "$ENV_FILE")
}

mount_nfs_storage() {
    [[ -n "$NFS_STORAGE_PATH" ]] || { echo "ERROR: nfs_storage_path is empty" >&2; return 1; }
    mkdir -p /data
    local entry="$NFS_STORAGE_PATH /data nfs4 sec=sys,nfsvers=4.1,_netdev 0 0"
    grep -Fqx -- "$entry" /etc/fstab || printf '%s\n' "$entry" >> /etc/fstab
    mountpoint -q /data || mount /data
}

wait_for_cluster() {
    for _ in {1..360}; do [[ -f "$SHARED_EGO_TOP/cluster_configured" ]] && return 0; sleep 10; done
    echo "ERROR: cluster_configured was not created within 3600 seconds" >&2
    return 1
}

copy_shared_certificates() {
    local security="$EGO_TOP/wlp/usr/shared/resources/security"
    mkdir -p "$security/ca"
    cp "$SHARED_EGO_TOP/security/servercertcasigned.pem" "$SHARED_EGO_TOP/security/cacert.pem" "$security/"
    cp "$SHARED_EGO_TOP/security/user.pem" "$SHARED_EGO_TOP/security/user.key" "$security/" 2>/dev/null || true
    if [[ "$SYMPHONY_SOAM_CERTIFICATE" == "true" ]]; then
        cp "$SHARED_EGO_TOP/security/ca/root.pem" "$SHARED_EGO_TOP/security/ca/intermediate.pem" "$security/ca/"
        local keytool="$EGO_TOP/jre/8.0.8.5/linux-x86_64/bin/keytool"
        "$keytool" -importcert -noprompt -alias soamrootcaalias -trustcacerts -file "$security/ca/root.pem" -keystore "$security/serverTrustStore.jks" -storepass Liberty
        "$keytool" -importcert -noprompt -alias soamintermediatecaalias -file "$security/ca/intermediate.pem" -keystore "$security/serverTrustStore.jks" -storepass Liberty
    fi
    local keytool="$EGO_TOP/jre/8.0.8.5/linux-x86_64/bin/keytool"
    cd "$security"
    "$keytool" -importcert -noprompt -alias caalias -file cacert.pem -keystore serverKeyStore.jks -storepass Liberty
    "$keytool" -import -noprompt -alias srvalias -file servercertcasigned.pem -keystore serverKeyStore.jks -storepass Liberty
    [[ -f user.pem ]] && "$keytool" -importcert -noprompt -alias soamalias -file user.pem -keystore serverKeyStore.jks -storepass Liberty
}

set_tcp_max_syn_backlog() {
    local setting='net.ipv4.tcp_max_syn_backlog=65536'
    grep -q '^net.ipv4.tcp_max_syn_backlog=' /etc/sysctl.conf && sed -i "s|^net.ipv4.tcp_max_syn_backlog=.*|$setting|" /etc/sysctl.conf || printf '%s\n' "$setting" >> /etc/sysctl.conf
    sysctl -w "$setting"
}

join_primary() {
    source "$EGO_TOP/profile.platform"
    egosetsudoers.sh -f; egosetrc.sh
    su - "$CLUSTER_ADMIN" -c "egoconfig join '$EGO_PRIMARY_HOST' -f"
    su - "$CLUSTER_ADMIN" -c "egoconfig mghost '$SHARED_EGO_TOP' -f"
}

restart_primary_with_lock() {
    local lock="$SHARED_EGO_TOP/restart.lock"
    for _ in {1..360}; do [[ ! -e "$lock" ]] && break; sleep 10; done
    touch "$lock"; chmod 0666 "$lock"
    ssh -o StrictHostKeyChecking=no -i /root/.ssh/id_rsa "$EGO_PRIMARY_HOST" 'systemctl restart ego'
    rm -f "$lock"
}

load_variables
configure_network
mount_nfs_storage
install -m 0600 "$SCRIPT_DIR/id_rsa" /root/.ssh/id_rsa
wait_for_cluster
copy_shared_certificates
set_tcp_max_syn_backlog
join_primary
systemctl enable --now ego
restart_primary_with_lock
