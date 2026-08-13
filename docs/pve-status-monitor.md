# PVE 摘要页硬件监控

[English](pve-status-monitor.en.md)

本项目使用自有单文件安装器实现 PVE 摘要页硬件监控，不在运行时下载第三方脚本，也不复制未声明许可证的上游源码。脚本采用与其他部署模块一致的交互确认，并保证重复安装幂等。

字段范围最初参考了 [PVE-manager-status](https://github.com/a904055262/PVE-manager-status)，实现、安装前基线和失败回滚逻辑均由本项目独立维护。

## 最终显示

```text
CPU状态       温度: 51°C | 固件温区: 28°C | 主频: 3.5 GHz
NVME0         <型号> | 53°C | 健康: 98% ...
GPU           Tesla P4 | 核心: 405 MHz | 温度: 42°C | 显存: 4096/8192 MiB | 显存温度: 不支持
```

- CPU 温度、固件温区和主频合并为一行。温度优先取 Intel `Package id 0`，同时兼容 AMD `Tctl` / `Tdie`；主频是所有逻辑 CPU 瞬时频率的算术平均值。
- NVMe 继续按 PVE Host 实际可见设备展示 SMART。
- GPU 展示第一块 Host 可见 NVIDIA GPU 的名称、核心时钟、核心温度和 framebuffer 已用/总量。
- 显存温度只有硬件和驱动支持时才显示；不支持时明确显示“`不支持`”。

## 字段含义和处理

| 原字段 | 含义 | 本项目处理 |
|---|---|---|
| `CPU: 51 (51 | 51 | ...)` | 第一个值是 CPU package 温度，括号内是各核心温度 | 只保留 package 温度 |
| `crit: 100` | 传感器报告的临界最高温度阈值，不是当前温度 | 不在摘要页显示 |
| `ACPITZ: 28` | ACPI 固件提供的 thermal zone；实际位置取决于主板/BIOS | 显示为 `固件温区: 28`，不冒充确定的主板或芯片组温度 |
| `NVME: 53, crit: 86` | `sensors` 提供的 NVMe 温度和阈值，与下方 SMART 行重复 | 不在温度行重复显示 |
| `MAX / MIN` | CPUFreq 策略允许的频率范围 | 不在摘要页显示 |
| `调速器: PERFORMANCE` | CPUFreq governor；`performance` 倾向请求策略允许的最高频率 | 不在摘要页显示 |

Linux 内核把 `temp*_crit` 定义为临界最高温度；Intel `coretemp` 同时提供 package 和各核心温度。CPUFreq governor 是内核的频率选择策略，其中 `performance` 请求策略上限。参考：

- [Linux hwmon sysfs interface](https://www.kernel.org/doc/html/latest/hwmon/sysfs-interface.html)
- [Linux coretemp driver](https://www.kernel.org/doc/html/latest/hwmon/coretemp.html)
- [Linux CPUFreq documentation](https://www.kernel.org/doc/html/latest/admin-guide/pm/cpufreq.html)

## 为什么只显示一块 NVMe

监控脚本只能读取 PVE Host 上仍然存在的 `/dev/nvme*` 控制器。若第二块 NVMe 已通过 PCIe 直通交给 FnOS，设备所有权属于 Guest，PVE 不能再对它执行 `smartctl`。这是正确的隔离边界，不是漏盘。

第二块盘应在 FnOS 内查看健康、温度和 SMART；不要尝试让 Host 绕过 PCIe 直通读取它。

## GPU 指标边界

GPU 数据来自 Host 的 `nvidia-smi`：

```bash
nvidia-smi \
  --query-gpu=name,clocks.current.graphics,temperature.gpu,memory.used,memory.total \
  --format=csv,noheader,nounits
```

显存温度单独查询；若返回空值、`N/A` 或不支持，页面显示“`不支持`”。NVIDIA 明确说明 Memory Current Temp 只在部分设备上可用。Tesla P4 是否返回该字段以现场驱动结果为准，不能用 GPU 核心温度冒充显存温度。[NVIDIA nvidia-smi documentation](https://docs.nvidia.com/deploy/nvidia-smi/index.html)

Host 的 framebuffer 使用量是物理 GPU 视角，不等同于某个 vGPU Guest 内单一进程的显存使用量。需要 Guest/应用级归因时，应在对应 Guest 内独立观察。

## 交互式幂等安装

直接运行，不接受子命令：

```bash
sudo ./scripts/02_pve_status_monitor.sh
```

安装器会：

1. 校验 PVE 和目标文件；检测到完整的 Solis 标记时直接成功返回，不改文件、不重启服务；
2. 检测到旧 `PVE-manager-status` 或不完整的 Solis 标记时停止，避免隐式迁移或覆盖；
3. 显示修改范围，获得人工确认后才安装缺失依赖；
4. 在 `/var/lib/solis-pvescript/pve-status-monitor/backups/<PVE版本>/` 保存并校验原始基线；
5. 只在工作副本中生成后端字段和前端组件，并同步摘要卡与同排图表高度，语法检查通过后才替换目标；
6. 写入或 `pveproxy` 重启失败时自动恢复安装前基线；成功后提示浏览器执行 `Shift+F5`。

NVMe SMART 不使用全局 SUID。安装器创建由 `visudo` 校验的精确规则，只允许 `www-data` 以 root 执行当前 Host NVMe 对应的固定 `smartctl <设备> -a -j` 命令。

`00_base.sh` 只负责基础配置，不调用监控。新 PVE 在完成基础配置后独立运行 `02_pve_status_monitor.sh`。

当前 PVE 版本的安装前基线是失败自动回滚所需资产，不属于临时垃圾。

PVE 包升级可能覆盖前端或 API 文件。升级后若监控消失，应重新运行安装器并再次验证页面。
