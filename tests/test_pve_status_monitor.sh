#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

export NODES_PM="$TMP_DIR/Nodes.pm"
export PVE_JS="$TMP_DIR/pvemanagerlib.js"
export PROXMOX_JS="$TMP_DIR/proxmoxlib.js"
export STATE_ROOT="$TMP_DIR/state"
export SMARTCTL_PATH="$TMP_DIR/smartctl"
export SUDOERS_FILE="$TMP_DIR/solis-pve-status-monitor.sudoers"

# shellcheck source=../scripts/02_pve_status_monitor.sh
source "$REPO_ROOT/scripts/02_pve_status_monitor.sh"

pveversion(){
  printf 'pve-manager/9.2.2/test\n'
}

SYSTEMCTL_RESTARTS=0
systemctl(){
  [[ "$1" == "restart" && "$2" == "pveproxy" ]]
  SYSTEMCTL_RESTARTS=$((SYSTEMCTL_RESTARTS + 1))
}

visudo(){
  return 0
}

discover_nvme_devices(){
  printf '/dev/nvme0\n'
}

require_pve_targets(){ :; }
require_runtime(){ :; }
CONFIRM_CALLS=0
confirm(){ CONFIRM_CALLS=$((CONFIRM_CALLS + 1)); }

cat > "$NODES_PM" <<'EOF'
package PVE::API2::Nodes;
my $res = {};
$res->{pveversion} = PVE::pvecfg::package() . "/" . PVE::pvecfg::version_text();
1;
EOF

cat > "$PVE_JS" <<'EOF'
Ext.define('PVE.node.StatusView', {
    alias: 'widget.pveNodeStatus',
    height: 350,
    items: [
        {
            itemId: 'version',
            colspan: 2,
            textField: 'pveversion',
            value: '',
        },
    ],
});
Ext.apply(me, {
    nodeStatus: nodeStatus,
    items: [{
        xtype: 'container',
        defaults: {
            minHeight: 360,
        },
    }],
});
EOF

printf 'native proxmox\n' > "$PROXMOX_JS"
patch_working_copies "$NODES_PM" "$PVE_JS" "/dev/nvme0"
grep -qF 'solis-pve-status-monitor:start' "$NODES_PM"
grep -qF 'solis-pve-status-monitor:start' "$PVE_JS"
grep -qF '固件温区:' "$PVE_JS"
grep -qF 'average / 1000' "$PVE_JS"
grep -qF "title: gettext('CPU状态')" "$PVE_JS"
! grep -qF "itemId: 'solisCpuFrequency'" "$PVE_JS"
grep -qF 'temperature.memory' "$NODES_PM"
grep -qF 'sudo -n /usr/sbin/smartctl /dev/nvme0 -a -j' "$NODES_PM"
grep -qF "title: gettext('NVME0')" "$PVE_JS"
grep -qF 'height: 434' "$PVE_JS"
grep -qF 'minHeight: 434' "$PVE_JS"
if command -v node >/dev/null 2>&1; then
  node --check "$PVE_JS" >/dev/null
fi

cat > "$NODES_PM" <<'EOF'
package PVE::API2::Nodes;
my $res = {};
$res->{pveversion} = PVE::pvecfg::package() . "/" . PVE::pvecfg::version_text();
1;
EOF
cat > "$PVE_JS" <<'EOF'
Ext.define('PVE.node.StatusView', {
    alias: 'widget.pveNodeStatus',
    height: 350,
    items: [
        {
            itemId: 'version',
            textField: 'pveversion',
        },
    ],
});
Ext.apply(me, {
    nodeStatus: nodeStatus,
    items: [{
        xtype: 'container',
        defaults: {
            minHeight: 360,
        },
    }],
});
EOF
main >/dev/null
has_solis_monitor
grep -qF 'www-data ALL=(root) NOPASSWD:' "$SUDOERS_FILE"
grep -qF '/dev/nvme0 -a -j' "$SUDOERS_FILE"
[[ -f "$(backup_dir)/SHA256SUMS" ]]
(cd "$(backup_dir)" && sha256sum --check SHA256SUMS >/dev/null)
[[ "$SYSTEMCTL_RESTARTS" -eq 1 ]]
[[ "$CONFIRM_CALLS" -eq 1 ]]
first_nodes_hash="$(sha256sum "$NODES_PM")"
first_js_hash="$(sha256sum "$PVE_JS")"
main >/dev/null
[[ "$(sha256sum "$NODES_PM")" == "$first_nodes_hash" ]]
[[ "$(sha256sum "$PVE_JS")" == "$first_js_hash" ]]
[[ "$SYSTEMCTL_RESTARTS" -eq 1 ]]
[[ "$CONFIRM_CALLS" -eq 1 ]]

! grep -qF '02_pve_status_monitor.sh' "$REPO_ROOT/scripts/00_base.sh"
grep -qF 'run 02_pve_status_monitor.sh' "$REPO_ROOT/setup.sh"
! grep -qF 'run 02_pve_status_monitor.sh install' "$REPO_ROOT/setup.sh"
grep -qF 'confirm "将安装 PVE 摘要页硬件监控' "$REPO_ROOT/scripts/02_pve_status_monitor.sh"
! grep -Eq '(^|[[:space:]])(migrate|update|restore|status)\)' "$REPO_ROOT/scripts/02_pve_status_monitor.sh"
[[ -f "$REPO_ROOT/scripts/00_base.sh" ]]
[[ -f "$REPO_ROOT/scripts/01_storage.sh" ]]
[[ -f "$REPO_ROOT/scripts/02_pve_status_monitor.sh" ]]
[[ ! -e "$REPO_ROOT/scripts/01_base.sh" ]]
[[ ! -e "$REPO_ROOT/scripts/02_storage.sh" ]]
! grep -R -E -q 'raw.githubusercontent.com/a904055262|PVE-manager-status/.+showtempcpufreq' "$REPO_ROOT/scripts"

cleanup_operation
rm -rf "$TMP_DIR"
trap - EXIT
printf 'PASS project-owned PVE status monitor\n'
