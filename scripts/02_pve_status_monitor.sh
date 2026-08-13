#!/usr/bin/env bash
# 02_pve_status_monitor.sh —— Solis 自有 PVE 摘要页硬件监控安装器
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NODES_PM="${NODES_PM:-/usr/share/perl5/PVE/API2/Nodes.pm}"
PVE_JS="${PVE_JS:-/usr/share/pve-manager/js/pvemanagerlib.js}"
PROXMOX_JS="${PROXMOX_JS:-/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js}"
STATE_ROOT="${STATE_ROOT:-/var/lib/solis-pvescript/pve-status-monitor}"
SMARTCTL_PATH="${SMARTCTL_PATH:-/usr/sbin/smartctl}"
SUDOERS_FILE="${SUDOERS_FILE:-/etc/sudoers.d/solis-pve-status-monitor}"
SOLIS_MARKER="solis-pve-status-monitor"
LEGACY_MARKER="modbyshowtempfreq"
WORK_DIR=""
OPERATION_SUCCEEDED=false

manager_version(){
  pveversion 2>/dev/null | sed -n 's#^pve-manager/\([^/[:space:]]*\).*#\1#p'
}

backup_dir(){
  local version
  version="$(manager_version)"
  [[ -n "$version" ]] || die "无法解析 PVE Manager 版本"
  printf '%s/backups/%s\n' "$STATE_ROOT" "$version"
}

cleanup_work_dir(){
  [[ -z "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"
}

remove_smartctl_sudoers(){
  if [[ -f "$SUDOERS_FILE" ]] && grep -qF "$SOLIS_MARKER" "$SUDOERS_FILE"; then
    rm -f -- "$SUDOERS_FILE"
  fi
}

cleanup_operation(){
  cleanup_work_dir
  [[ "$OPERATION_SUCCEEDED" == true ]] || remove_smartctl_sudoers
}

require_pve_targets(){
  need_root
  need_pve9
  [[ -f "$NODES_PM" ]] || die "未找到 $NODES_PM"
  [[ -f "$PVE_JS" ]] || die "未找到 $PVE_JS"
}

ensure_runtime_packages(){
  local -a packages=()
  command -v perl >/dev/null 2>&1 || packages+=(perl)
  command -v sensors >/dev/null 2>&1 || packages+=(lm-sensors)
  command -v smartctl >/dev/null 2>&1 || packages+=(smartmontools)
  command -v sudo >/dev/null 2>&1 || packages+=(sudo)
  ((${#packages[@]} == 0)) && return 0
  msg_info "安装监控依赖：${packages[*]}"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get -y install "${packages[@]}"
}

require_runtime(){
  require_pve_targets
  ensure_runtime_packages
  command -v perl >/dev/null 2>&1 || die "缺少 perl"
  command -v sensors >/dev/null 2>&1 || die "缺少 lm-sensors；请先安装 lm-sensors"
  command -v smartctl >/dev/null 2>&1 || die "缺少 smartctl；请先安装 smartmontools"
  command -v sudo >/dev/null 2>&1 || die "缺少 sudo"
  command -v visudo >/dev/null 2>&1 || die "缺少 visudo"
}

has_marker(){
  local marker="$1" file="$2"
  [[ -f "$file" ]] && grep -qF "$marker" "$file"
}

has_legacy_monitor(){
  has_marker "$LEGACY_MARKER" "$NODES_PM" ||
    has_marker "$LEGACY_MARKER" "$PVE_JS" ||
    has_marker "$LEGACY_MARKER" "$PROXMOX_JS"
}

has_solis_monitor(){
  has_marker "$SOLIS_MARKER" "$NODES_PM" && has_marker "$SOLIS_MARKER" "$PVE_JS"
}

create_baseline(){
  local target_dir
  target_dir="$(backup_dir)"
  mkdir -p "$target_dir"
  if [[ ! -e "$target_dir/Nodes.pm" ]]; then
    cp -a -- "$NODES_PM" "$target_dir/Nodes.pm"
  fi
  if [[ ! -e "$target_dir/pvemanagerlib.js" ]]; then
    cp -a -- "$PVE_JS" "$target_dir/pvemanagerlib.js"
  fi
  (cd "$target_dir" && sha256sum Nodes.pm pvemanagerlib.js > SHA256SUMS)
}

discover_nvme_devices(){
  local device
  for device in /dev/nvme[0-9]; do
    [[ -e "$device" ]] && printf '%s\n' "$device"
  done
}

configure_smartctl_sudoers(){
  local temporary
  local -a devices=()
  mapfile -t devices < <(discover_nvme_devices)
  ((${#devices[@]} > 0)) || return 0
  if [[ -e "$SUDOERS_FILE" ]] && ! grep -qF "$SOLIS_MARKER" "$SUDOERS_FILE"; then
    die "拒绝覆盖非 Solis 管理的 sudoers 文件：$SUDOERS_FILE"
  fi
  temporary="$(mktemp "${SUDOERS_FILE}.tmp.XXXXXX")"
  {
    printf '# %s\n' "$SOLIS_MARKER"
    for device in "${devices[@]}"; do
      printf 'www-data ALL=(root) NOPASSWD: %s %s -a -j\n' "$SMARTCTL_PATH" "$device"
    done
  } > "$temporary"
  chmod 0440 "$temporary"
  visudo -cf "$temporary" >/dev/null || { rm -f -- "$temporary"; die "SMART sudoers 语法检查失败"; }
  mv -f -- "$temporary" "$SUDOERS_FILE"
}

patch_working_copies(){
  local nodes_copy="$1" js_copy="$2" test_nvme_devices="${3:-}"
  perl - "$nodes_copy" "$js_copy" "$test_nvme_devices" <<'PERL'
use strict;
use warnings;
use utf8;

my ($nodes_path, $js_path, $test_nvme_devices) = @ARGV;
my $marker = 'solis-pve-status-monitor';

sub read_utf8 {
    my ($path) = @_;
    open my $fh, '<:encoding(UTF-8)', $path or die "cannot read $path: $!\n";
    local $/;
    my $value = <$fh>;
    close $fh or die "cannot close $path: $!\n";
    return $value;
}

sub write_utf8 {
    my ($path, $value) = @_;
    open my $fh, '>:encoding(UTF-8)', $path or die "cannot write $path: $!\n";
    print {$fh} $value or die "cannot write $path: $!\n";
    close $fh or die "cannot close $path: $!\n";
}

my $nodes = read_utf8($nodes_path);
my $js = read_utf8($js_path);
die "Solis marker already exists in working copy\n" if $nodes =~ /\Q$marker\E/ || $js =~ /\Q$marker\E/;

my @nvme = length($test_nvme_devices // '')
    ? grep { length } split(/\s+/, $test_nvme_devices)
    : sort glob('/dev/nvme[0-9]');
die "invalid NVMe device path\n" if grep { !m{\A/dev/nvme\d+\z} } @nvme;
my $node_block = <<'NODE_BLOCK';
        # solis-pve-status-monitor:start
        $res->{solis_thermal} = `sensors -A 2>/dev/null`;
        $res->{solis_cpu_freq} = `grep -i '^cpu MHz' /proc/cpuinfo 2>/dev/null`;
        $res->{solis_gpu} = `
            if command -v nvidia-smi >/dev/null 2>&1; then
                gpu_base=\$(nvidia-smi --query-gpu=name,clocks.current.graphics,temperature.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1)
                gpu_mem_temp=\$(nvidia-smi --query-gpu=temperature.memory --format=csv,noheader,nounits 2>/dev/null | head -n1 || true)
                [ -n "\$gpu_mem_temp" ] || gpu_mem_temp=N/A
                [ -z "\$gpu_base" ] || printf '%s, %s\n' "\$gpu_base" "\$gpu_mem_temp"
            fi
        `;
NODE_BLOCK

for my $index (0 .. $#nvme) {
    my $device = $nvme[$index];
    $node_block .= "        \$res->{solis_nvme$index} = `/usr/bin/sudo -n /usr/sbin/smartctl $device -a -j 2>/dev/null`;\n";
}
$node_block .= "        # solis-pve-status-monitor:end\n";

my $node_count = ($nodes =~ s{
    (^\s*\$res->\{pveversion\}\s*=\s*PVE::pvecfg::package\(\)\s*\.\s*"/"\s*\.\s*PVE::pvecfg::version_text\(\);\R)
}{$1\n$node_block}mx);
die "Nodes.pm anchor count must be 1, got $node_count\n" if $node_count != 1;

my $js_block = <<'JS_BLOCK';
        // solis-pve-status-monitor:start
        {
            itemId: 'solisCpuStatus',
            colspan: 2,
            printBar: false,
            title: gettext('CPU状态'),
            multiField: true,
            renderer: function ({ data }) {
                let thermal = data.solis_thermal || '';
                let blocks = thermal.trim().split(/\s+(?=^\w+-)/m);
                let cpu = blocks.find((item) => /^(coretemp|k10temp|zenpower)-/i.test(item));
                let acpi = blocks.find((item) => /^acpitz-/i.test(item));
                let cpuTemperature;
                if (cpu) {
                    cpuTemperature = cpu.match(/(?:Package id 0|Tctl|Tdie):\s+\+?([\d.]+)(?=.?°C)/i);
                    cpuTemperature ??= cpu.match(/:\s+\+?([\d.]+)(?=.?°C)/);
                }
                let acpiTemperature = acpi?.match(/:\s+\+?([\d.]+)(?=.?°C)/);
                let cpuText = cpuTemperature ? Number(cpuTemperature[1]).toFixed(0) : 'N/A';
                let acpiText = acpiTemperature ? Number(acpiTemperature[1]).toFixed(0) : 'N/A';
                let frequencies = data.solis_cpu_freq?.match(/(?<=^cpu[^\d]+)\d+(?:\.\d+)?/gim);
                let frequencyText = 'N/A';
                if (frequencies?.length) {
                    let average = frequencies.reduce((sum, item) => sum + Number(item), 0) / frequencies.length;
                    frequencyText = (average / 1000).toFixed(1);
                }
                return `温度: ${cpuText}°C | 固件温区: ${acpiText}°C | 主频: ${frequencyText} GHz`;
            },
        },
        {
            itemId: 'solisGpu',
            colspan: 2,
            printBar: false,
            title: gettext('GPU'),
            textField: 'solis_gpu',
            renderer: function (value) {
                if (!value?.trim()) {
                    return '未检测到可用 NVIDIA GPU';
                }
                let fields = value.trim().split(/\s*,\s*/);
                if (fields.length < 5) {
                    return 'NVIDIA GPU 数据不可用';
                }
                let [name, clock, temperature, used, total, memoryTemperature = 'N/A'] = fields;
                let memoryTemperatureText = /^(N\/A|\[Not Supported\])$/i.test(memoryTemperature)
                    ? '不支持'
                    : `${memoryTemperature}°C`;
                return `${name} | 核心: ${clock} MHz | 温度: ${temperature}°C | 显存: ${used}/${total} MiB | 显存温度: ${memoryTemperatureText}`;
            },
        },
JS_BLOCK

for my $index (0 .. $#nvme) {
    $js_block .= <<"NVME_BLOCK";
        {
            itemId: 'solisNvme$index',
            colspan: 2,
            printBar: false,
            title: gettext('NVME$index'),
            textField: 'solis_nvme$index',
            renderer: function (value) {
                try {
                    let data = JSON.parse(value);
                    if (!data.model_name) {
                        return '无法读取硬盘信息';
                    }
                    let temperature = data.temperature?.current;
                    let log = data.nvme_smart_health_information_log;
                    let health = log?.percentage_used === undefined ? '' : ` | 健康: \${100 - log.percentage_used}%,0E: \${log.media_errors ?? 'N/A'}`;
                    let power = data.power_on_time?.hours === undefined ? '' : ` | 通电: \${data.power_on_time.hours}时,次: \${data.power_cycle_count ?? 'N/A'}`;
                    let read = log?.data_units_read ? (log.data_units_read / 1956882).toFixed(1) : '';
                    let write = log?.data_units_written ? (log.data_units_written / 1956882).toFixed(1) : '';
                    let io = read && write ? ` | R/W: \${read}T/\${write}T` : '';
                    let smart = data.smart_status?.passed;
                    let smartText = smart === undefined ? '' : ` | SMART: \${smart ? '正常' : '警告!'}`;
                    return `\${data.model_name}\${temperature === undefined ? '' : ` | \${temperature}°C`}\${health}\${power}\${io}\${smartText}`;
                } catch (_error) {
                    return '无法获得有效信息';
                }
            },
        },
NVME_BLOCK
}
$js_block .= "        // solis-pve-status-monitor:end\n";

my $item_pattern = qr{
    (\{\s*itemId:\s*['"](?:version|pveversion)['"][\s\S]*?textField:\s*['"]pveversion['"][\s\S]*?\n\s*\},)
}x;
my $js_count = ($js =~ s{$item_pattern}{$1\n$js_block});
die "PVE status item anchor count must be 1, got $js_count\n" if $js_count != 1;

my $added_height = 28 * (2 + scalar(@nvme));
my $status_height;
my $height_count = ($js =~ s{
    (alias:\s*['"]widget\.pveNodeStatus['"][\s\S]{0,400}?height:\s*)(\d+)
}{ $status_height = $2 + $added_height; $1 . $status_height }ex);
die "PVE status height anchor count must be 1, got $height_count\n" if $height_count != 1;

my $summary_height_count = ($js =~ s{
    (nodeStatus:\s*nodeStatus,[\s\S]{0,900}?defaults:\s*\{[\s\S]{0,300}?minHeight:\s*)\d+
}{$1 . $status_height}ex);
die "PVE summary minHeight anchor count must be 1, got $summary_height_count\n" if $summary_height_count != 1;

write_utf8($nodes_path, $nodes);
write_utf8($js_path, $js);
PERL
}

apply_solis_monitor(){
  local target_dir nodes_copy js_copy
  has_solis_monitor && { OPERATION_SUCCEEDED=true; msg_ok "Solis 监控已经安装"; return 0; }
  if has_marker "$SOLIS_MARKER" "$NODES_PM" || has_marker "$SOLIS_MARKER" "$PVE_JS"; then
    die "检测到不完整的 Solis 监控标记；请先 restore"
  fi

  mkdir -p "$STATE_ROOT"
  WORK_DIR="$(mktemp -d "$STATE_ROOT/work.XXXXXX")"
  nodes_copy="$WORK_DIR/Nodes.pm"
  js_copy="$WORK_DIR/pvemanagerlib.js"
  cp -a -- "$NODES_PM" "$nodes_copy"
  cp -a -- "$PVE_JS" "$js_copy"
  patch_working_copies "$nodes_copy" "$js_copy"
  grep -qF "$SOLIS_MARKER" "$nodes_copy" || die "Nodes.pm 工作副本缺少 Solis 标记"
  grep -qF "$SOLIS_MARKER" "$js_copy" || die "前端工作副本缺少 Solis 标记"
  perl -c "$nodes_copy" >/dev/null 2>&1 || die "修改后的 Nodes.pm 语法检查失败"

  create_baseline
  configure_smartctl_sudoers
  target_dir="$(backup_dir)"
  if ! cp -a -- "$nodes_copy" "$NODES_PM" || ! cp -a -- "$js_copy" "$PVE_JS"; then
    cp -a -- "$target_dir/Nodes.pm" "$NODES_PM"
    cp -a -- "$target_dir/pvemanagerlib.js" "$PVE_JS"
    die "写入失败，已恢复安装前基线"
  fi
  has_solis_monitor || {
    cp -a -- "$target_dir/Nodes.pm" "$NODES_PM"
    cp -a -- "$target_dir/pvemanagerlib.js" "$PVE_JS"
    die "写入后标记验证失败，已恢复安装前基线"
  }
  if ! systemctl restart pveproxy; then
    cp -a -- "$target_dir/Nodes.pm" "$NODES_PM"
    cp -a -- "$target_dir/pvemanagerlib.js" "$PVE_JS"
    systemctl restart pveproxy || true
    die "pveproxy 重启失败，已恢复安装前基线"
  fi
  OPERATION_SUCCEEDED=true
  msg_ok "Solis PVE 摘要页硬件监控已安装"
  msg_info "请使用 Shift+F5 强制刷新浏览器"
}

main(){
  [[ $# -eq 0 ]] || die "本脚本不接受子命令，请直接运行：./scripts/02_pve_status_monitor.sh"
  require_pve_targets
  if has_solis_monitor; then
    OPERATION_SUCCEEDED=true
    msg_ok "Solis PVE 摘要页硬件监控已经安装，无需重复修改"
    return 0
  fi
  if has_marker "$SOLIS_MARKER" "$NODES_PM" || has_marker "$SOLIS_MARKER" "$PVE_JS"; then
    die "检测到不完整的 Solis 监控标记；请先恢复 PVE Manager 原始文件"
  fi
  has_legacy_monitor && die "检测到旧 PVE-manager-status；请先恢复 PVE Manager 原始文件"
  confirm "将安装 PVE 摘要页硬件监控、保存当前版本基线并重启 pveproxy，继续?" || die "已取消"
  trap cleanup_operation EXIT
  require_runtime
  apply_solis_monitor
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
