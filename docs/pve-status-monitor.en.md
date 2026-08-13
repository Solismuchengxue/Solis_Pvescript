# PVE Summary Hardware Monitor

[中文](pve-status-monitor.md)

The project uses a project-owned, single-file installer for PVE summary hardware monitoring. It neither downloads a third-party script at runtime nor copies upstream source that lacks a declared license. The script uses the same interactive confirmation pattern as the other deployment modules and guarantees idempotent reruns.

The metric scope was initially informed by [PVE-manager-status](https://github.com/a904055262/PVE-manager-status); the implementation, pre-installation baseline, and automatic failure rollback are independently maintained by this project.

## Resulting Display

```text
CPU status         Temp: 51°C | Firmware zone: 28°C | Frequency: 3.5 GHz
NVME0             <model> | 53°C | Health: 98% ...
GPU               Tesla P4 | Core: 405 MHz | Temp: 42°C | VRAM: 4096/8192 MiB | VRAM temp: unsupported
```

- CPU temperature, firmware zone, and frequency share one row. Temperature prefers Intel `Package id 0` and also supports AMD `Tctl` / `Tdie`; frequency is the arithmetic mean across all logical CPUs.
- NVMe SMART data covers only devices visible to the PVE Host.
- GPU data covers the first NVIDIA GPU visible to the Host: name, graphics clock, GPU-core temperature, and framebuffer used/total.
- VRAM temperature is shown only when both the hardware and driver support it; otherwise it is explicitly reported as unsupported.

## Field Meaning and Presentation

| Original field | Meaning | Project behavior |
|---|---|---|
| `CPU: 51 (51 | 51 | ...)` | The first value is the CPU package temperature; values in parentheses are per-core temperatures | Keep the package temperature only |
| `crit: 100` | Critical maximum reported by the sensor, not the current temperature | Hide it from the summary |
| `ACPITZ: 28` | An ACPI firmware thermal zone whose physical meaning depends on the board/BIOS | Display it as `Firmware zone: 28` without claiming it is a specific board or chipset sensor |
| `NVME: 53, crit: 86` | NVMe temperature and limit from `sensors`, duplicated by the SMART row | Do not repeat it in the temperature row |
| `MAX / MIN` | Frequency limits exposed by the CPUFreq policy | Hide them from the summary |
| `Governor: PERFORMANCE` | The CPUFreq governor; `performance` requests the highest frequency allowed by the policy | Hide it from the summary |

The Linux kernel defines `temp*_crit` as a critical maximum temperature. Intel `coretemp` exposes both package and per-core readings. CPUFreq governors select frequency policy, and `performance` requests the policy maximum. References:

- [Linux hwmon sysfs interface](https://www.kernel.org/doc/html/latest/hwmon/sysfs-interface.html)
- [Linux coretemp driver](https://www.kernel.org/doc/html/latest/hwmon/coretemp.html)
- [Linux CPUFreq documentation](https://www.kernel.org/doc/html/latest/admin-guide/pm/cpufreq.html)

## Why Only One NVMe Device Appears

The monitor can read only `/dev/nvme*` controllers still owned by the PVE Host. If the second NVMe controller is passed through to FnOS over PCIe, the Guest owns that device and PVE can no longer run `smartctl` against it. This is the intended isolation boundary, not a missing-drive bug.

Inspect the second device's health, temperature, and SMART data inside FnOS. Do not bypass PCIe ownership from the Host.

## GPU Metric Boundaries

The Host metrics come from `nvidia-smi`:

```bash
nvidia-smi \
  --query-gpu=name,clocks.current.graphics,temperature.gpu,memory.used,memory.total \
  --format=csv,noheader,nounits
```

VRAM temperature is queried separately. Empty, `N/A`, or unsupported results are displayed as unsupported. NVIDIA documents that Memory Current Temp is available only on supported devices. Whether a Tesla P4 reports it depends on the actual driver result; GPU-core temperature must never be presented as VRAM temperature. See the [NVIDIA nvidia-smi documentation](https://docs.nvidia.com/deploy/nvidia-smi/index.html).

Host framebuffer usage is the physical-GPU view and is not equivalent to the memory used by one process inside one vGPU Guest. Observe the relevant Guest separately when per-VM or per-application attribution is required.

## Interactive Idempotent Installation

Run the script directly without a subcommand:

```bash
sudo ./scripts/02_pve_status_monitor.sh
```

The installer:

1. validates PVE and the target files; when complete Solis markers are already present, it returns successfully without modifying files or restarting services;
2. stops when it detects legacy `PVE-manager-status` markers or an incomplete Solis installation, avoiding implicit migration or overwrite;
3. shows the change scope and installs missing dependencies only after human confirmation;
4. stores and verifies the original baseline under `/var/lib/solis-pvescript/pve-status-monitor/backups/<PVE-version>/`;
5. generates backend fields and frontend components only in working copies, synchronizes the status card and peer chart heights, and replaces targets only after checks pass;
6. automatically restores the pre-installation baseline if a write or `pveproxy` restart fails, and prompts for a browser `Shift+F5` after success.

NVMe SMART does not use a global SUID bit. The installer creates a `visudo`-validated exact rule that allows `www-data` to run only the fixed `smartctl <device> -a -j` command for each current Host NVMe device as root.

`00_base.sh` handles base configuration only and does not invoke monitoring. A fresh PVE host runs `02_pve_status_monitor.sh` independently after base configuration.

The pre-installation baseline for the current PVE version is required for automatic failure rollback and is not transient garbage.

A PVE package upgrade may replace the API or frontend files. Rerun the installer and verify the page if the monitor disappears after an upgrade.
