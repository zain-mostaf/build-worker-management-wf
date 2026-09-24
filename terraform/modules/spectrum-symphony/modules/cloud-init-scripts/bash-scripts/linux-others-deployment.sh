#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/linux-master-deployment-env.json"
value() { jq -r --arg key "$1" '.[$key] // empty' "$ENV_FILE"; }
EGO_TOP="$(value EGO_TOP)"; EGO_TOP="${EGO_TOP:-/opt/ibm/spectrumcomputing}"
CLUSTER_ADMIN="$(value CLUSTER_ADMIN)"; CLUSTER_ADMIN="${CLUSTER_ADMIN:-egoadmin}"
CLUSTER_ID="$(value cluster_id)"; SHARED_EGO_TOP="$(value SHARED_EGO_TOP)"; SHARED_EGO_TOP="${SHARED_EGO_TOP:-/data/$CLUSTER_ID/sym732}"
PRIMARY="$(value ego_primary_host)"; NFS_STORAGE_PATH="$(value nfs_storage_path)"
mkdir -p /data
if [[ -n "$NFS_STORAGE_PATH" ]]; then
  entry="$NFS_STORAGE_PATH /data nfs4 sec=sys,nfsvers=4.1,_netdev 0 0"
  grep -Fqx "$entry" /etc/fstab || printf '%s\n' "$entry" >> /etc/fstab
  mountpoint -q /data || mount /data
fi
install -m 0600 "$SCRIPT_DIR/id_rsa" /root/.ssh/id_rsa
for attempt in {1..360}; do [[ -f "$SHARED_EGO_TOP/cluster_configured" ]] && break; sleep 10; done
[[ -f "$SHARED_EGO_TOP/cluster_configured" ]]
mkdir -p "$EGO_TOP/wlp/usr/shared/resources/security"
cp "$SHARED_EGO_TOP/security/"{servercertcasigned.pem,cacert.pem} "$EGO_TOP/wlp/usr/shared/resources/security/" 2>/dev/null || true
cp "$SHARED_EGO_TOP/security/"{user.pem,user.key} "$EGO_TOP/wlp/usr/shared/resources/security/" 2>/dev/null || true
source "$EGO_TOP/profile.platform"; egosetsudoers.sh -f; egosetrc.sh
su - "$CLUSTER_ADMIN" -c "egoconfig join $PRIMARY -f"
su - "$CLUSTER_ADMIN" -c "egoconfig mghost $SHARED_EGO_TOP -f"
systemctl enable --now ego
lock="$SHARED_EGO_TOP/restart.lock"
for attempt in {1..360}; do [[ ! -e "$lock" ]] && break; sleep 10; done
touch "$lock"
ssh -o StrictHostKeyChecking=no -i /root/.ssh/id_rsa "$PRIMARY" 'systemctl restart ego'
rm -f "$lock"
