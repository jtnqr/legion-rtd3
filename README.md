# legion-rtd3

Comprehensive Linux Hybrid Graphics Runtime D3cold (RTD3) power management and system optimization for AMD APU + NVIDIA dGPU laptops (tested on Lenovo Legion 5 15ACH6H, AMD Ryzen 5000 / 6000 / 7000 APUs, NVIDIA RTX 30-series / 40-series under Fedora / GNOME Wayland).

---

## Problems Solved

1. **dGPU Battery Drain in Hybrid Mode (`D0` lock)**:
   * Desktop applications (Telegram, Electron apps, Brave/Chrome, Steam CEF) probe Vulkan ICDs and EGL vendors at startup, opening `/dev/dri/renderD129` or `/dev/nvidiactl` and locking the dGPU awake in `D0` (~20W–25W continuous battery drain).
   * **Fix**: Pins default session Vulkan to AMD Radeon ICD via dynamic environment generation, allowing background apps to run purely on the APU while the dGPU sleeps in `D3cold` (0W).

2. **Monitoring Tools Waking the dGPU (`nvtop`, `btop`)**:
   * Hardware monitors dynamically query `libnvidia-ml.so` (NVML) on startup, triggering immediate PCIe wakeups even if no discrete GPU tasks are running.
   * **Fix**: Implements a high-performance C interceptor (`libno_nvml.so`) with cached sysfs path resolution and direct symbol stubs. If the dGPU is asleep (`suspended`), NVML calls return `NULL` / `NVML_ERROR_DRIVER_NOT_LOADED` gracefully so monitors only display the AMD APU without waking NVIDIA. If a game is active or `prime-run` is used, NVML queries pass through unhindered.

3. **Steam Client Forcing Discrete GPU**:
   * Upstream Valve `steam.desktop` specifies `PrefersNonDefaultGPU=true`, causing GNOME Shell to inject PRIME offload variables into the Steam client and all `steamwebhelper` web processes.
   * **Fix**: Provides a launcher override pinning the Steam client to the APU (`legion-rtd3 fix-launchers`), while preserving discrete GPU offload for games via `prime-run %command%`.

4. **External Display Detection & Lingering DRM Surface Wake Locks**:
   * On battery in `D3cold`, plugging a USB-C dock fails DP Alt Mode link training because the hardwired discrete GPU is unpowered. Conversely, when an external monitor is unplugged, upstream DRM drivers can leave runtime PM usage counters stuck in `active` (NVIDIA issue #759).
   * **Fix**: Deploys automated udev rules (`82-dock-dgpu-wake.rules` and `81-nvidia-hotplug-pm.rules`) to wake the dGPU upon USB-C dock connection for immediate DP link training, and re-arm PCIe `power/control = auto` upon display or dock disconnect.

5. **Universal Multi-Mode Compatibility**:
   * Dynamically inspects the PCI bus at session login. Works out of the box across **Hybrid**, **Dedicated** (BIOS MUX switch or EnvyControl), and **Integrated** modes without manual edits to `/etc/environment`.

---

## Repository Structure

```text
legion-rtd3/
├── Makefile                                    # Zero-dependency build & install
├── README.md
├── bin/
│   ├── legion-rtd3                            # Unified control, diagnostic & audit CLI
│   ├── gpu-guard                              # Universal dispatcher for CLI monitors
│   └── prime-run                              # Discrete NVIDIA offload launcher
├── src/
│   └── no_nvml.c                              # Sleep-aware NVML C interceptor & symbol stub
├── etc/
│   ├── systemd/user-environment-generators/
│   │   └── 10-gpu-mode.sh                     # Dynamic session mode generator
│   ├── tlp.d/
│   │   └── 98-amdgpu-abm.conf                 # ABM disable drop-in for TLP (stops color crush)
│   └── udev/rules.d/
│       ├── 61-mutter-primary-gpu.rules        # Mutter primary GPU preference for AMD
│       ├── 80-nvidia-pm.rules                 # PCIe Runtime D3cold rules
│       ├── 81-nvidia-hotplug-pm.rules         # DRM hotplug re-arm PM rule
│       └── 82-dock-dgpu-wake.rules            # USB-C dock connect wake / disconnect re-arm rule
├── desktop/
│   └── steam.desktop                          # APU-pinned Steam client launcher
└── patches/
    └── refresh-rate-governor.patch            # Optional extension patch for Extended VBLANK panels
```

---

## Installation

```bash
git clone https://github.com/jtnqr/legion-rtd3.git
cd legion-rtd3
make
sudo make install
```

After installation, log out and log back in (or reboot) to initialize the dynamic session environment.

---

## CLI Usage & Diagnostics

`legion-rtd3` includes a built-in diagnostic and audit tool:

```bash
# Check real-time power state, discharge wattage, and display mode:
legion-rtd3 status

# Run a complete system audit for rogue wake locks and service misconfigurations:
legion-rtd3 doctor

# Automatically override desktop launchers forcing discrete GPU (e.g. Steam):
legion-rtd3 fix-launchers
```

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
