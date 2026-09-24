#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/linux-master-deployment-env.json"

check_jq() {
    command -v jq >/dev/null 2>&1 && return 0
    if command -v dnf >/dev/null 2>&1; then
        dnf install -y jq
    elif command -v yum >/dev/null 2>&1; then
        yum install -y jq
    else
        echo "ERROR: jq, dnf, and yum are unavailable" >&2
        return 1
    fi
    command -v jq >/dev/null 2>&1 || { echo "ERROR: jq installation failed" >&2; return 1; }
}

value() {
    jq -r --arg key "$1" '.[$key] // empty' "$ENV_FILE"
}

load_variables() {
    [[ -r "$ENV_FILE" ]] || { echo "ERROR: Missing JSON file: $ENV_FILE" >&2; return 1; }
    jq empty "$ENV_FILE" >/dev/null || { echo "ERROR: Invalid JSON: $ENV_FILE" >&2; return 1; }

    EGO_TOP="$(value EGO_TOP)"; EGO_TOP="${EGO_TOP:-/opt/ibm/spectrumcomputing}"
    CLUSTER_ADMIN="$(value CLUSTER_ADMIN)"; CLUSTER_ADMIN="${CLUSTER_ADMIN:-egoadmin}"
    CLUSTER_ID="$(value cluster_id)"
    CLUSTER_DOMAIN="$(value cluster_domain)"
    NFS_STORAGE_PATH="$(value nfs_storage_path)"
    SHARED_EGO_TOP="$(value SHARED_EGO_TOP)"; SHARED_EGO_TOP="${SHARED_EGO_TOP:-/data/$CLUSTER_ID/sym732}"
    DNS_SERVER="$(value dns_server_ips)"; DNS_SERVER="${DNS_SERVER:-161.26.0.10}"
    SYMPHONY_VERSION="$(value SYMPHONY_VERSION)"; SYMPHONY_VERSION="${SYMPHONY_VERSION:-7.3.2}"
    EGO_BASE_PORT="$(value ego_base_port)"; EGO_BASE_PORT="${EGO_BASE_PORT:-7869}"
    WORKER_OS="$(value worker_os)"; WORKER_OS="${WORKER_OS:-linux}"
}

configure_network() {
    local connection="System eth0"
    nmcli -t -f NAME connection show "$connection" >/dev/null 2>&1 || { echo "ERROR: Missing connection $connection" >&2; return 1; }
    systemctl restart NetworkManager
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
        local route_connection gateway priority table cidr
        route_connection="$(jq -r '.conn_name' <<<"$route")"
        gateway="$(jq -r '.gateway' <<<"$route")"
        priority="$(jq -r '.priority' <<<"$route")"
        table="$(jq -r '.table' <<<"$route")"
        cidr="$(jq -r '.cidr' <<<"$route")"
        nmcli connection modify "$route_connection" +ipv4.routes "0.0.0.0/0 $gateway table=$table"
        nmcli connection modify "$route_connection" +ipv4.routing-rules "priority $priority from $cidr table $table, priority $priority to $cidr table $table"
    done < <(jq -c '.additional_routes[]?' "$ENV_FILE")
}

mount_nfs_storage() {
    [[ -n "$NFS_STORAGE_PATH" ]] || { echo "ERROR: nfs_storage_path is empty" >&2; return 1; }
    mkdir -p /data
    local entry="$NFS_STORAGE_PATH /data nfs4 sec=sys,nfsvers=4.1,_netdev 0 0"
    grep -Fqx -- "$entry" /etc/fstab || printf '%s\n' "$entry" >> /etc/fstab
    mountpoint -q /data || mount /data
}

initialize_storage() {
    local marker="$SHARED_EGO_TOP/cluster_configured"
    if [[ ! -f "$marker" ]]; then
        rm -rf -- "$SHARED_EGO_TOP"
        mkdir -p "$SHARED_EGO_TOP"
        chown "$CLUSTER_ADMIN:$CLUSTER_ADMIN" "$SHARED_EGO_TOP"
        chmod 0755 "$SHARED_EGO_TOP"
    fi
}

update_cluster_id() {
    local marker="$SHARED_EGO_TOP/cluster_configured"
    [[ -f "$marker" ]] && return 0
    local old_file="$EGO_TOP/kernel/conf/ego.cluster.IBMCloudSym73?Cluster"
    [[ -e "$old_file" ]] && mv "$old_file" "$EGO_TOP/kernel/conf/ego.cluster.$CLUSTER_ID"
    sed -i -E "s/IBMCloudSym73.*/$CLUSTER_ID/" "$EGO_TOP/kernel/conf/ego.shared"
}

include_ego_attributes() {
    local file="$EGO_TOP/kernel/conf/ego.shared" attribute
    while IFS= read -r attribute; do
        [[ -z "$attribute" ]] && continue
        grep -Fqx -- "$attribute" "$file" || sed -i "/^End Resource/i\$attribute" "$file"
    done < <(jq -r '.ego_new_attributes[]?' "$ENV_FILE")
}

move_deployment_key() {
    mkdir -p /root/.ssh
    [[ -f "$SCRIPT_DIR/id_rsa" ]] && install -m 0600 "$SCRIPT_DIR/id_rsa" /root/.ssh/id_rsa
}

configure_webgui_tls() {
    local marker="$SHARED_EGO_TOP/cluster_configured" ssl_marker="$EGO_TOP/ssl_cert_configured"
    local security="$EGO_TOP/wlp/usr/shared/resources/security" shared="$SHARED_EGO_TOP/security"
    [[ -f "$marker" || -f "$ssl_marker" ]] && return 0
    mkdir -p "$security" "$shared"
    if [[ "$(value symphony_webgui_certificate)" == "true" ]]; then
        cp "$SCRIPT_DIR/servercertcasigned.pem" "$SCRIPT_DIR/cacert.pem" "$security/"
    else
        local keytool="$EGO_TOP/jre/8.0.8.5/linux-x86_64/bin/keytool"
        cd "$security"
        "$keytool" -genkeypair -noprompt -alias srvalias -dname "CN=*${CLUSTER_DOMAIN},O=Platform,C=CA" -keystore serverKeyStore.jks -storepass Liberty -keypass Liberty -keyalg rsa -validity 1095 -keysize 2048 -sigalg SHA256withRSA -ext "san:dns:$HOSTNAME"
        "$keytool" -certreq -alias srvalias -file srvcertreq.csr -storepass Liberty -keystore serverKeyStore.jks -ext "san:dns:$HOSTNAME"
        "$keytool" -gencert -infile srvcertreq.csr -outfile servercertcasigned.pem -alias caalias -keystore caKeyStore.jks -storepass Liberty -validity 1095 -ext "san:dns:$HOSTNAME"
    fi
    cp "$security/servercertcasigned.pem" "$security/cacert.pem" "$shared/"
}

configure_soam_certificates() {
    local marker="$SHARED_EGO_TOP/cluster_configured" ssl_marker="$EGO_TOP/ssl_cert_configured"
    local security="$EGO_TOP/wlp/usr/shared/resources/security" ca_dir="$EGO_TOP/wlp/usr/shared/resources/security/ca"
    local shared="$SHARED_EGO_TOP/security" keytool="$EGO_TOP/jre/8.0.8.5/linux-x86_64/bin/keytool"
    [[ -f "$marker" || -f "$ssl_marker" ]] && return 0
    mkdir -p "$security" "$ca_dir" "$shared"
    if [[ "$(value symphony_soam_certificate)" == "true" ]]; then
        cp "$SCRIPT_DIR/root.pem" "$SCRIPT_DIR/intermediate.pem" "$ca_dir/"
        cp "$SCRIPT_DIR/user.pem" "$SCRIPT_DIR/user.key" "$security/"
        cat "$ca_dir/root.pem" "$ca_dir/intermediate.pem" > "$security/cacert.pem"
        "$keytool" -importcert -noprompt -alias soamrootcaalias -trustcacerts -file "$ca_dir/root.pem" -keystore "$security/serverTrustStore.jks" -storepass Liberty
        "$keytool" -importcert -noprompt -alias soamintermediatecaalias -file "$ca_dir/intermediate.pem" -keystore "$security/serverTrustStore.jks" -storepass Liberty
    else
        cd "$security"
        "$keytool" -genkeypair -noprompt -alias soamalias -dname "CN=soam.$CLUSTER_DOMAIN,O=Platform,C=CA" -keystore serverKeyStore.jks -storepass Liberty -keypass Liberty -keyalg rsa -validity 1095 -keysize 2048 -sigalg SHA256withRSA -ext "san:dns:soam.$HOSTNAME"
        "$keytool" -certreq -alias soamalias -file soamcertreq.csr -storepass Liberty -keystore serverKeyStore.jks -ext "san:dns:soam.$HOSTNAME"
        "$keytool" -gencert -infile soamcertreq.csr -outfile soamcertcasigned.pem -alias caalias -keystore caKeyStore.jks -storepass Liberty -validity 1095 -ext "san:dns:soam.$HOSTNAME"
        "$keytool" -importkeystore -srckeystore serverKeyStore.jks -destkeystore user.p12 -srcstoretype JKS -deststoretype PKCS12 -srcstorepass Liberty -deststorepass Liberty -srcalias soamalias -destalias soamalias -srckeypass Liberty -destkeypass Liberty -noprompt
        openssl pkcs12 -in user.p12 -nodes -nocerts -passin pass:Liberty | grep -A 50 'BEGIN PRIVATE KEY' > user.key
        openssl x509 -in soamcertcasigned.pem -inform DER -out user.pem -outform PEM
        [[ -f "$security/cacert.pem" ]] || cp "$security/ca.pem" "$security/cacert.pem" 2>/dev/null || true
    fi
    cp "$security/user.pem" "$security/user.key" "$security/cacert.pem" "$shared/"
    "$keytool" -importcert -noprompt -alias caalias -file "$security/cacert.pem" -keystore "$security/serverKeyStore.jks" -storepass Liberty
    "$keytool" -importcert -noprompt -alias soamalias -file "$security/user.pem" -keystore "$security/serverKeyStore.jks" -storepass Liberty
    touch "$ssl_marker"
    chmod 0755 "$ssl_marker"
}

configure_symphony_primary() {
    local marker="$SHARED_EGO_TOP/cluster_configured" file="$EGO_TOP/soam/$SYMPHONY_VERSION/eservice/sd.xml"
    [[ -f "$marker" ]] && return 0
    local temp="${file}.tmp" insertion
    insertion="<ego:EnvironmentVariable name=\"SSM_SDK_ADDR\">$(value symphony_ssm_port_range)</ego:EnvironmentVariable>"
    if ! grep -q 'name="SSM_SDK_ADDR"' "$file"; then
        awk -v insertion="$insertion" '{print} /name="SD_SDK_PORT"/ && !done {print insertion; done=1}' "$file" > "$temp" && mv "$temp" "$file"
    fi
    if [[ "$(value symphony_soam_certificate)" == "true" ]] && ! grep -q 'name="SD_SOAP_TRANSPORT"' "$file"; then
        awk '1; /name="SD_SDK_PORT"/ && !done {print "<ego:EnvironmentVariable name=\"SD_SOAP_TRANSPORT\">TCPIPv4SSL</ego:EnvironmentVariable>"; print "<ego:EnvironmentVariable name=\"SD_SOAP_TRANSPORT_ARG\">$EGO_DEFAULT_TS_PARAMS</ego:EnvironmentVariable>"; print "<ego:EnvironmentVariable name=\"SDSOAPCLIENT_ARG\">$EGO_CLIENT_TS_PARAMS</ego:EnvironmentVariable>"; print "<ego:EnvironmentVariable name=\"SSM_SDK_TRANSPORT\">TCPIPv4SSL</ego:EnvironmentVariable>"; print "<ego:EnvironmentVariable name=\"SSM_SDK_TRANSPORT_ARG\">$EGO_DEFAULT_TS_PARAMS</ego:EnvironmentVariable>"; print "<ego:EnvironmentVariable name=\"SDK_TRANSPORT\">TCPIPv4SSL</ego:EnvironmentVariable>"; print "<ego:EnvironmentVariable name=\"SDK_TRANSPORT_ARG\">$EGO_CLIENT_TS_PARAMS</ego:EnvironmentVariable>"; print "<ego:EnvironmentVariable name=\"SD_SDK_TRANSPORT\">TCPIPv4SSL</ego:EnvironmentVariable>"; print "<ego:EnvironmentVariable name=\"SD_SDK_TRANSPORT_ARG\">$EGO_DEFAULT_TS_PARAMS</ego:EnvironmentVariable>"; done}' "$file" > "$temp" && mv "$temp" "$file"
    fi
}

disable_perf_service() {
    sed -i 's|localhost|$HOSTNAME|g' "$EGO_TOP/perf/conf/datasource.xml" "$EGO_TOP/eservice/esc/conf/services/derby_service.xml" 2>/dev/null || true
    sed -i 's|AUTOMATIC|MANUAL|g' "$EGO_TOP/eservice/esc/conf/services/derby_service.xml" "$EGO_TOP/eservice/esc/conf/services/plc_service.xml" "$EGO_TOP/eservice/esc/conf/services/purger_service.xml" 2>/dev/null || true
}

set_tcp_max_syn_backlog() {
    local setting='net.ipv4.tcp_max_syn_backlog=65536'
    grep -q '^net.ipv4.tcp_max_syn_backlog=' /etc/sysctl.conf && sed -i "s|^net.ipv4.tcp_max_syn_backlog=.*|$setting|" /etc/sysctl.conf || printf '%s\n' "$setting" >> /etc/sysctl.conf
    sysctl -w "$setting"
}

deploy_ego_conf() { [[ -f "$SHARED_EGO_TOP/cluster_configured" ]] || { cp "$SCRIPT_DIR/ego.conf" "$EGO_TOP/kernel/conf/ego.conf"; chown egoadmin "$EGO_TOP/kernel/conf/ego.conf"; chmod 0644 "$EGO_TOP/kernel/conf/ego.conf"; }; }

configure_primary_cluster() {
    [[ -f "$SHARED_EGO_TOP/cluster_configured" ]] && return 0
    source "$EGO_TOP/profile.platform"; egosetsudoers.sh -f; egosetrc.sh
    local password; password="$(printf '%s' "$(value symphony_password)" | base64 --decode)"
    su - "$CLUSTER_ADMIN" -c "egoconfig join $(hostname).$CLUSTER_DOMAIN -f"
    printf -v password_command 'egoconfig setpassword -x %q -f' "$password"
    su - "$CLUSTER_ADMIN" -c "$password_command"
}

set_symphony_entitlement() { [[ -f "$SHARED_EGO_TOP/cluster_configured" ]] || { source "$EGO_TOP/profile.platform"; egosetsudoers.sh -f; egosetrc.sh; su - "$CLUSTER_ADMIN" -c "egoconfig setentitlement $EGO_TOP/kernel/conf/sym_adv_entitlement.dat"; }; }
configure_management_host() { source "$EGO_TOP/profile.platform"; egosetsudoers.sh -f; egosetrc.sh; su - "$CLUSTER_ADMIN" -c "egoconfig mghost $SHARED_EGO_TOP -f"; }
create_symphony_folders() { [[ -f "$SHARED_EGO_TOP/cluster_configured" ]] && return 0; for folder in "$SHARED_EGO_TOP/kernel/audit" "$SHARED_EGO_TOP/kernel/work/data" "$SHARED_EGO_TOP/hostfactory"; do mkdir -p "$folder"; chown -R "$CLUSTER_ADMIN:$CLUSTER_ADMIN" "$folder"; chmod -R 0755 "$folder"; done; }
set_ego_base_port() { [[ -f "$SHARED_EGO_TOP/cluster_configured" ]] && return 0; local port="$(value ego_base_port)"; [[ "$port" =~ ^[0-9]+$ ]] || { echo "ERROR: Invalid ego_base_port: $port" >&2; return 1; }; source "$EGO_TOP/profile.platform"; egosetsudoers.sh -f; egosetrc.sh; su - "$CLUSTER_ADMIN" -c "egoconfig setbaseport '$port'"; }
share_server_internal_xml() { local dest="$SHARED_EGO_TOP/kernel/conf/webapp/server_internal.xml"; mkdir -p "$(dirname "$dest")"; cp "$EGO_TOP/kernel/conf/webapp/server_internal.xml" "$dest"; chown egoadmin "$dest"; chmod 0644 "$dest"; }
include_configured_marker() { [[ "$WORKER_OS" == windows ]] && return 0; local marker="$SHARED_EGO_TOP/cluster_configured"; mkdir -p "$(dirname "$marker")"; touch "$marker"; chown "$CLUSTER_ADMIN" "$marker"; chmod 0644 "$marker"; }
start_ego_service() { systemctl enable --now ego; }
wait_for_vemkd_port() { local port=$(($1 + 1)); sleep 30; for _ in {1..120}; do timeout 1 bash -c "</dev/tcp/127.0.0.1/$port" 2>/dev/null && return 0; sleep 5; done; echo "ERROR: vemkd port $port unavailable" >&2; return 1; }
configure_windows_workers() { [[ "$WORKER_OS" == windows ]] || return 0; local password=$(printf '%s' "$(value symphony_password)" | base64 --decode); source "$EGO_TOP/profile.platform"; egosh user logon -u Admin -x "$password"; egosh ego execpasswd -u "$CLUSTER_ADMIN" -x "$password" -noverify; sed -i -E 's#<ExecutionUser>egoadmin</ExecutionUser>#<ExecutionUser>.\\egoadmin</ExecutionUser>#' "$SHARED_EGO_TOP/kernel/conf/ConsumerTrees.xml"; soamview "app symping$SYMPHONY_VERSION" -p > /tmp/sp.xml; soamreg /tmp/sp.xml -f; systemctl restart ego; include_configured_marker; }

check_jq
load_variables
configure_network
mount_nfs_storage
initialize_storage
update_cluster_id
include_ego_attributes
move_deployment_key
configure_webgui_tls
configure_soam_certificates
set_tcp_max_syn_backlog
configure_symphony_primary
disable_perf_service
deploy_ego_conf
configure_primary_cluster
set_symphony_entitlement
configure_management_host
create_symphony_folders
set_ego_base_port
share_server_internal_xml
include_configured_marker
start_ego_service
wait_for_vemkd_port "$EGO_BASE_PORT"
configure_windows_workers
