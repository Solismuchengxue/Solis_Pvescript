# NVIDIA vGPU Driver Installation Guide

[中文](vgpu-driver-guide.md)

The vGPU path spans three driver and licensing domains: the **PVE Host**, an **FnOS/Linux Guest**, and a **Windows 11 Guest**. Use the section that matches the system you are configuring.

The public repository does not include NVIDIA driver packages. Driver archives are large and license-restricted; users must obtain them legally and keep them outside Git as defined by `.gitignore`.

## Constraints to Review First

| Item | Project rule |
|---|---|
| Host vs Guest driver | Use the same supported vGPU branch and the exact version selected for this deployment, for example `535.309.01` on both sides |
| Driver vs kernel | R535 combinations with newer PVE kernels are highly version-sensitive; follow the compatibility-kernel policy in `04_iommu.sh` and accept only an actual DKMS build plus post-reboot verification |
| vGPU profile | Use a **Q profile** for CUDA or transcoding. Under the recorded vGPU 16.14 baseline, P4-2Q=`nvidia-64` and P4-4Q=`nvidia-65`; do not treat a B profile as a compute profile |
| Licensing | Use a valid entitlement to create an official NVIDIA CLS or DLS instance and generate a Client Configuration Token |

## Obtaining the Driver Legally

NVIDIA vGPU drivers do not have an open-source replacement. The documented evaluation path is NVIDIA's official 90-day vGPU evaluation:

1. Open the NVIDIA vGPU product page and request a Free Trial / 90-Day Evaluation.
2. After approval, sign in to the NVIDIA Licensing Portal / Application Hub and download the Linux KVM package.
3. Select a vGPU 16.x / R535 release whose support matrix still includes the Pascal-based Tesla P4.
4. Extract the package and identify the three relevant artifacts:

   ```text
   Host_Drivers/NVIDIA-Linux-x86_64-535.xxx.xx-vgpu-kvm.run
   Guest_Drivers/NVIDIA-Linux-x86_64-535.xxx.xx-grid.run
   Guest_Drivers/<version>_grid_win10_win11_...dch_64bit....exe
   ```

Evaluation requests may require organization information and a business email address. Treat the entitlement and download state shown in the NVIDIA Licensing Portal as authoritative rather than relying only on notification email.

The project never downloads NVIDIA's official driver automatically. Place a legally obtained Host package in `drivers/`, or use `drivers/fetch.sh` to retrieve a Host package from an authorized private NAS.

---

## PVE Host

Place the NVIDIA vGPU **Host/KVM** driver in `drivers/`. Its filename must include `vgpu-kvm`:

```text
drivers/NVIDIA-Linux-x86_64-<version>-vgpu-kvm.run
```

`scripts/05_vgpu_driver.sh` discovers and installs that package:

```bash
# Discover a *vgpu*kvm*.run file under drivers/
./scripts/05_vgpu_driver.sh

# Or select one explicitly
DRIVER_RUN=./drivers/NVIDIA-Linux-x86_64-535.309.01-vgpu-kvm.run \
  ./scripts/05_vgpu_driver.sh
```

### Add or Replace a vGPU Profile

By default, `08_vm_attach.sh` adds a vGPU only to a VM that does not already have one. It stops if an existing vGPU is detected, preventing an accidental second device.

To replace the only existing profile, stop the VM and set `REPLACE_EXISTING=1` explicitly:

```bash
# Add one P4-4Q
VMID=101 MDEV_TYPE=nvidia-65 ./scripts/08_vm_attach.sh

# Replace the only existing profile on a stopped VM
REPLACE_EXISTING=1 VMID=101 MDEV_TYPE=nvidia-65 \
  ./scripts/08_vm_attach.sh
```

Replacement preserves the existing `hostpci` index, PCI address, and other options and changes only `mdev=`. It requires a stopped VM with exactly one existing vGPU. Time-sliced profiles active on the same physical GPU must use a compatible framebuffer allocation; if the target profile reports `available_instances=0`, the script stops before changing the VM.

---

## FnOS / Linux Guest

These steps apply to a Debian-family Linux Guest. Prerequisites:

- the VM already has a vGPU attached through `08_vm_attach.sh`;
- the Guest driver matches the deployment's Host vGPU version, for example `NVIDIA-Linux-x86_64-535.309.01-grid.run`.

### 1. Transfer the Guest Driver

Use an authorized and controlled path:

- download it from a private WebDAV or other file service without placing credentials in commands, documentation, or Git; or
- transfer it over SSH to a Guest directory such as `/vol<pool>/<uid>/drivers/`.

`drivers/fetch.sh` retrieves a **Host driver** into the repository's `drivers/` directory. It does not transfer a Guest driver into FnOS.

### 2. Install the Guest Driver

```bash
sudo apt update
sudo apt install -y build-essential dkms linux-headers-$(uname -r) pkg-config

cd /vol1/1000/drivers/
chmod +x NVIDIA-Linux-x86_64-535.309.01-grid.run
sudo ./NVIDIA-Linux-x86_64-535.309.01-grid.run
```

Recommended installer choices:

| Prompt | Choice | Rationale |
|---|---|---|
| Register modules with DKMS | **Yes** | Rebuilds modules for supported kernel upgrades |
| Install 32-bit compatibility libraries | **No** | Not required for the documented 64-bit headless Guest |
| Run `nvidia-xconfig` | **No** | The Guest does not use an X display stack |
| Other prompts | Default | Review the selected driver release notes if behavior differs |

Reboot and verify:

```bash
sudo reboot
nvidia-smi
```

`nvidia-smi` should show the allocated profile, such as GRID P4-4Q, its framebuffer, and the expected driver version.

### 3. Configure Official NVIDIA Licensing

Create an official CLS or DLS instance with a valid entitlement and generate a Client Configuration Token. The following commands configure the Guest only; they do not create a license service:

```bash
sudo mkdir -p /etc/nvidia/ClientConfigToken
sudo cp <path-to-client-configuration-token> /etc/nvidia/ClientConfigToken/
sudo chmod 744 /etc/nvidia/ClientConfigToken/*.tok

# Configure /etc/nvidia/gridd.conf according to the matching
# NVIDIA Client Licensing guide and the actual entitlement/profile.

sudo systemctl restart nvidia-gridd
nvidia-smi -q | grep -i -A3 license
```

Feature types and defaults differ between vGPU releases. Follow the [NVIDIA Client Licensing User Guide](https://docs.nvidia.com/vgpu/latest/grid-licensing-user-guide/) that matches the installed branch. Do not treat an unknown token or configuration file as a substitute for a valid license.

### 4. Configure the NVIDIA Container Toolkit

The NVIDIA Container Toolkit is a Linux Guest package and Docker runtime integration, not a long-running container. Use either NVIDIA's official APT packages or a distribution/NAS package—not both.

The example below uses the site-verified `1.19.1-1` baseline. Before installation, confirm that `nvidia-smi`, licensing, and `/dev/nvidia-uvm` work, and preserve the existing Docker configuration.

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor --yes \
      -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -fsSL \
  https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null

sudo apt-get update
NVIDIA_CONTAINER_TOOLKIT_VERSION=1.19.1-1
sudo apt-get install -y \
  "nvidia-container-toolkit=${NVIDIA_CONTAINER_TOOLKIT_VERSION}" \
  "nvidia-container-toolkit-base=${NVIDIA_CONTAINER_TOOLKIT_VERSION}" \
  "libnvidia-container-tools=${NVIDIA_CONTAINER_TOOLKIT_VERSION}" \
  "libnvidia-container1=${NVIDIA_CONTAINER_TOOLKIT_VERSION}"

if sudo test -f /etc/docker/daemon.json; then
  sudo cp -a /etc/docker/daemon.json \
    "/etc/docker/daemon.json.pre-nvidia-$(date +%Y%m%d-%H%M%S)"
fi

sudo nvidia-ctk runtime configure --runtime=docker
sudo dockerd --validate --config-file=/etc/docker/daemon.json
sudo systemctl restart docker
```

`nvidia-ctk` registers the NVIDIA runtime without making it the default. Ordinary containers continue to use `runc`.

```bash
docker info --format 'runtimes={{json .Runtimes}} default={{.DefaultRuntime}}'
docker ps
docker run --rm --gpus all \
  nvidia/cuda:12.2.2-base-ubuntu22.04 nvidia-smi -L
```

A passing CUDA container proves only the baseline CUDA/runtime path. Validate NVENC with a real non-direct-play transcode and validate inference features with an actual workload and GPU usage evidence. After a Guest kernel upgrade, recheck DKMS, `nvidia-smi`, UVM, licensing, Docker runtime registration, and container GPU access.

---

## Windows 11 Guest

Prerequisites:

- the VM already has a vGPU attached through `08_vm_attach.sh`;
- the Windows Guest driver matches the deployment's Host vGPU release.

Do not set the VM display adapter to `none` before the NVIDIA driver is installed and the Guest can see the vGPU. Removing the temporary VirtIO/standard display too early can make the VM console inaccessible.

### 1. Transfer and Install the Driver

Start the VM:

```bash
qm start <VMID>
```

Transfer the Windows Guest package through an authorized WebDAV, browser download, SMB share, or another controlled channel. Do not place file-service addresses, usernames, or passwords in public documentation or shell history.

Run the NVIDIA installer, complete the standard installation, and reboot Windows.

After reboot, open Device Manager and confirm that an NVIDIA device appears under Display adapters. An unlicensed status at this stage is expected until Guest licensing is configured.

### 2. Configure Licensing

1. Obtain a Client Configuration Token from the NVIDIA Licensing Portal or an official DLS instance.
2. Place it under:

   ```text
   C:\Program Files\NVIDIA Corporation\vGPU Licensing\ClientConfigToken\
   ```

3. Restart **NVIDIA Display Container LS** from `services.msc`, or reboot Windows.
4. Check the licensing state in NVIDIA Control Panel or the NVIDIA Container notification.

Windows Guest behavior depends on the installed vGPU branch and profile. Use the corresponding NVIDIA Client Licensing documentation as the authority.
