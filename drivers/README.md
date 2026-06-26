# drivers/ —— 放置 NVIDIA vGPU host 驱动

`05_vgpu_driver.sh` 会在本目录查找 host 驱动并安装。

## 放什么

NVIDIA vGPU **host** 驱动（注意是 host/KVM 版，不是普通显卡驱动）：

```
NVIDIA-Linux-x86_64-<版本>-vgpu-kvm.run
```

- **Tesla P4 = Pascal 架构**，建议 **16.x（535.xxx）** 分支。
- 文件名务必含 `vgpu-kvm`（host 端）。guest 端驱动是另一个文件，装进虚拟机里，**且必须与 host 同分支**。

## 从哪获取（90 天评估，合法免费）

vGPU 驱动无开源替代，合法免费途径是 NVIDIA 官方 **90 天评估**（不是购买）：

1. NVIDIA 官网 → Data Center → **Virtual GPU (vGPU)** → 申请 **Free Trial / 90-Day Evaluation**。
2. 通过后登录 **NVIDIA Licensing Portal (NLP) / Application Hub** 下载软件包，hypervisor 选 **Linux KVM**。
3. 版本选 **vGPU 16.x（= 535 驱动）**——P4 是 Pascal，下载前对照支持列表确认该版本仍含 P4。
4. 解压软件包，分别取出：
   - `Host_Drivers/NVIDIA-Linux-x86_64-535.xxx.xx-vgpu-kvm.run` → 放**本目录**，给 `05` 用
   - `Guest_Drivers/...`（Windows `.exe` / Linux `.run`）→ 装进虚拟机

> ⚠️ 评估申请表通常要填**组织名 + 业务邮箱**，个人 Gmail 可能需审核或被拒——这是实际门槛。
> 脚本**不联网下载官方驱动**，请自行准备 `.run` 放到这里。

## License 闭环（无需买授权）

guest 满速需 license。评估期内可用 NVIDIA 评估 license；**评估到期后、或干脆从一开始，就用本仓库 `07_dls.sh` 自建 fastapi-dls 发 token** 给 guest，即可持续 `Licensed`——连 NVIDIA 的 license server 都不用碰。

## 版本配套（重要）

| 项 | 约束 |
|----|------|
| host 驱动 vs guest 驱动 | **必须同一 vGPU 分支**（如都用 16.x/535） |
| 驱动 vs 内核 | 535 在 6.8+ 内核多半需打补丁；故 04 已 pin 内核 |
| License | guest 满速需 License → 见 `07_dls.sh`（自建 DLS） |

## 用法

```bash
# 默认自动找本目录下的 *vgpu*kvm*.run
./05_vgpu_driver.sh
# 或显式指定
DRIVER_RUN=./drivers/NVIDIA-Linux-x86_64-535.230.02-vgpu-kvm.run ./05_vgpu_driver.sh
```
