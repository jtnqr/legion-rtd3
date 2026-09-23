# legion-rtd3

Comprehensive Linux Hybrid Graphics Runtime D3cold (RTD3) power management and display color stabilization for AMD APU + NVIDIA dGPU laptops (tested on Lenovo Legion 5 15ACH6H, AMD Ryzen 5000 / 6000 APUs, NVIDIA RTX 30-series / 40-series under Fedora / GNOME Wayland).

---

## Problems Solved

1. **dGPU Battery Drain in Hybrid Mode (`D0` lock)**:
   * By default, desktop applications (Telegram, Electron apps, Brave/Chrome, Steam CEF) probe Vulkan ICDs and EGL vendors at startup, inadvertently opening `/dev/dri/renderD129` or `/dev/nvidiactl` and locking the dGPU awake in `D0` (~20W–25W continuous battery drain).
   * **Fix**: Pins default session Vulkan to AMD Radeon ICD and prioritizes Mesa EGL, allowing background apps to run purely on the APU while the dGPU sleeps in `D3cold` (0W).

2. **Monitoring Tools Waking the dGPU (`nvtop`, `btop`)**:
   * Hardware monitors dynamically query `libnvidia-ml.so` (NVML) on startup, triggering immediate PCIe wakeups even if no discrete GPU tasks are running.
   * **Fix**: Implements a sleep-aware C interceptor (`libno_nvml.so`) that checks `/sys/bus/pci/.../runtime_status`. If the dGPU is asleep (`suspended`), NVML queries return `NULL` gracefully so monitors only display the AMD APU without waking NVIDIA. If a game is active or `prime-run` is used, NVML queries pass through unhindered.

3. **Steam Client Forcing Discrete GPU**:
   * Upstream Valve `steam.desktop` specifies `PrefersNonDefaultGPU=true`, causing GNOME Shell to inject PRIME offload variables into the Steam client and all `steamwebhelper` web processes.
   * **Fix**: Provides a launcher override pinning the Steam client to the APU, while preserving discrete GPU offload for games via `prime-run %command%`.

4. **Panel Color Shift & Contrast Crush at 60Hz / Battery**:
   * Switching high-refresh gaming displays (e.g. BOE NV156FHM-NY8) to 60Hz via standard CVT modes drops the pixel clock to ~172 MHz (far below the 193 kHz line rate design spec), underdriving the T-CON voltage ladder and causing a warm/yellow tint.
   * AMD Adaptive Backlight Management (ABM) dynamically alters pixel luminance to save battery, crushing dark shadows and washing out highlights.
   * **Fix**: Disables AMDGPU ABM in TLP (`AMDGPU_ABM_LEVEL=0`) and patches `refresh-rate-governor` to select custom Extended VBLANK EDID modes (maintaining native 401.21 MHz clock) with unmanaged `sdr-native` colorimetry.

5. **Universal Mode Compatibility**:
   * Dynamically inspects the PCI bus at session login. Works out of the box across **Hybrid**, **Dedicated** (BIOS MUX switch or EnvyControl), and **Integrated** modes without manual edits to `/etc/environment`.

---

## Repository Structure

```text
legion-rtd3/
├── Makefile                                    # Zero-dependency build & install
├── README.md
├── bin/
│   ├── gpu-guard                              # Universal dispatcher for CLI monitors
│   └── prime-run                              # Discrete NVIDIA offload launcher
├── src/
│   └── no_nvml.c                              # Sleep-aware NVML C interceptor
├── etc/
│   ├── glvnd/egl_vendor.d/
│   │   └── 00_mesa.json                       # Package-update resilient Mesa EGL priority
│   ├── systemd/user-environment-generators/
│   │   └── 10-gpu-mode.sh                     # Dynamic session mode generator
│   ├── tlp.d/
│   │   └── 98-amdgpu-abm.conf                 # ABM disable drop-in for TLP
│   └── udev/rules.d/
│       ├── 61-mutter-primary-gpu.rules        # Mutter primary GPU preference for AMD
│       └── 80-nvidia-pm.rules                 # PCIe Runtime D3cold rules
├── desktop/
│   └── steam.desktop                          # APU-pinned Steam client launcher
└── patches/
    └── refresh-rate-governor.patch            # GNOME extension patch for Extended VBLANK
```

---

## Installation

```bash
git clone https://github.com/42-evey/legion-rtd3.git
cd legion-rtd3
make
sudo make install
```

After installation, log out and log back in (or reboot) to initialize the dynamic session environment.

---

## Verification

Check hardware power state while on battery or idle:
```bash
cat /sys/bus/pci/devices/0000:01:00.0/power_state
# Expected: D3cold (or D3hot when plugged into AC)

cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status
# Expected: suspended
```

Verify monitoring tools do not wake the dGPU:
```bash
nvtop -s
btop
# Check power_state again -> remains D3cold / suspended
```

Verify explicit discrete GPU offload works on demand:
```bash
prime-run nvidia-smi
# Wakes into D0, reports GPU stats, and returns to D3cold within ~10 seconds
```

---

## Uninstallation

```bash
cd legion-rtd3
sudo make uninstall
```

Restores default system configurations with zero leftover files.

---

## License

GPL-3.0-or-later. See [LICENSE](LICENSE) for details.
