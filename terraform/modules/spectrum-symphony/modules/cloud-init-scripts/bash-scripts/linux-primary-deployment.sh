#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/linux-master-deployment-env.json"
value() { jq -r --arg key "$1" '.[$key] // empty' "$ENV_FILE"; }
EGO_TOP="$(value EGO_TOP)"; EGO_TOP="${EGO_TOP:-/opt/ibm/spectrumcomputing}"
CLUSTER_ADMIN="$(value CLUSTER_ADMIN)"; CLUSTER_ADMIN="${CLUSTER_ADMIN:-egoadmin}"
CLUSTER_ID="$(value cluster_id)"
SHARED_EGO_TOP="$(value SHARED_EGO_TOP)"; SHARED_EGO_TOP="${SHARED_EGO_TOP:-/data/$CLUSTER_ID/sym732}"
CLUSTER_DOMAIN="$(value cluster_domain)"
NFS_STORAGE_PATH="$(value nfs_storage_path)"
DNS_SERVER="$(value dns_server_ips)"; DNS_SERVER="${DNS_SERVER:-161.26.0.10}"
EGO_BASE_PORT="$(value ego_base_port)"; EGO_BASE_PORT="${EGO_BASE_PORT:-7869}"
SYMPHONY_VERSION="$(value SYMPHONY_VERSION)"; SYMPHONY_VERSION="${SYMPHONY_VERSION:-7.3.2}"
append_once() { grep -Fqx -- "$2" "$1" 2>/dev/null || printf '%s\n' "$2" >> "$1"; }
run_admin() { su - "$CLUSTER_ADMIN" -c "$*"; }

systemctl restart NetworkManager
nmcli connection modify 'System eth0' ipv4.dns "$DNS_SERVER" ipv4.dns-search "$CLUSTER_DOMAIN" 802-3-ethernet.mtu 9000 || true
nmcli connection up 'System eth0' || true
jq -c '.additional_routes[]?' "$ENV_FILE" | while read -r route; do
  connection="$(jq -r '.conn_name' <<<"$route")"
  gateway="$(jq -r '.gateway' <<<"$route")"; table="$(jq -r '.table' <<<"$route")"
  priority="$(jq -r '.priority' <<<"$route")"; cidr="$(jq -r '.cidr' <<<"$route")"
  nmcli connection modify "$connection" +ipv4.routes "0.0.0.0/0 $gateway table=$table" || true
  nmcli connection modify "$connection" +ipv4.routing-rules "priority $priority from $cidr table $table, priority $priority to $cidr table $table" || true
done

mkdir -p /data "$SHARED_EGO_TOP"
if [[ -n "$NFS_STORAGE_PATH" ]]; then
  entry="$NFS_STORAGE_PATH /data nfs4 sec=sys,nfsvers=4.1,_netdev 0 0"
  grep -Fqx "$entry" /etc/fstab || printf '%s\n' "$entry" >> /etc/fstab
  mountpoint -q /data || mount /data
fi
marker="$SHARED_EGO_TOP/cluster_configured"
if [[ ! -f "$marker" ]]; then
  mv "$EGO_TOP/kernel/conf/ego.cluster.IBMCloudSym73"* "$EGO_TOP/kernel/conf/ego.cluster.$CLUSTER_ID" 2>/dev/null || true
  sed -i -E "s/IBMCloudSym73.*/$CLUSTER_ID/" "$EGO_TOP/kernel/conf/ego.shared" || true
  mkdir -p "$SHARED_EGO_TOP/kernel/audit" "$SHARED_EGO_TOP/kernel/work/data" "$SHARED_EGO_TOP/hostfactory"
fi
append_once "$EGO_TOP/kernel/conf/ego.shared" 'workerPool  String  ()       ()              (Custom Attribute - workerPool)'
append_once "$EGO_TOP/kernel/conf/ego.shared" 'techStack  String  ()       ()              (Custom Attribute - techStack)'

if [[ -f "$SCRIPT_DIR/servercertcasigned.pem" ]]; then
  mkdir -p "$EGO_TOP/wlp/usr/shared/resources/security" "$SHARED_EGO_TOP/security"
  cp "$SCRIPT_DIR/servercertcasigned.pem" "$EGO_TOP/wlp/usr/shared/resources/security/"
  cat "$SCRIPT_DIR/root.pem" "$SCRIPT_DIR/intermediate.pem" > "$EGO_TOP/wlp/usr/shared/resources/security/cacert.pem"
  cp "$SCRIPT_DIR/user.pem" "$SCRIPT_DIR/user.key" "$EGO_TOP/wlp/usr/shared/resources/security/" 2>/dev/null || true
  cp "$EGO_TOP/wlp/usr/shared/resources/security/"{servercertcasigned.pem,cacert.pem} "$SHARED_EGO_TOP/security/"
  cp "$EGO_TOP/wlp/usr/shared/resources/security/"{user.pem,user.key} "$SHARED_EGO_TOP/security/" 2>/dev/null || true
fi

append_once /etc/sysctl.conf 'net.ipv4.tcp_max_syn_backlog'; sysctl -p || true
if [[ ! -f "$marker" ]]; then
  cp "$SCRIPT_DIR/ego.conf" "$EGO_TOP/kernel/conf/ego.conf"
  source "$EGO_TOP/profile.platform"
  egosetsudoers.sh -f; egosetrc.sh
  run_admin "egoconfig join \`hostname\`.$CLUSTER_DOMAIN -f"
  password="$(value symphony_password)"
  run_admin "egoconfig setpassword -x \$(echo -n '$password' | base64 -d) -f"
  run_admin "egoconfig setentitlement $EGO_TOP/kernel/conf/sym_adv_entitlement.dat"
  run_admin "egoconfig mghost $SHARED_EGO_TOP -f"
  run_admin "egoconfig setbaseport $EGO_BASE_PORT"
  touch "$marker"
fi
systemctl enable --now ego
for attempt in {1..120}; do timeout 1 bash -c "</dev/tcp/127.0.0.1/$((EGO_BASE_PORT + 1))" && exit 0; sleep 5; done
exit 1
