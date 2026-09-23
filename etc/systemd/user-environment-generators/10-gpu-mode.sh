#!/bin/sh
# Dynamic GPU environment generator for systemd user session
# Adapts dynamically to Dedicated (BIOS MUX or EnvyControl), Hybrid, and Integrated modes

has_amd=0
has_nvidia=0

# Detect display-capable GPUs from PCI class 03xxxx (VGA / 3D / Display)
for dev in /sys/bus/pci/devices/*; do
    [ -f "$dev/class" ] || continue
    class=$(cat "$dev/class" 2>/dev/null || true)
    case "$class" in
        0x0300*|0x0302*|0x0380*)
            vendor=$(cat "$dev/vendor" 2>/dev/null || true)
            [ "$vendor" = "0x1002" ] && has_amd=1
            [ "$vendor" = "0x10de" ] && has_nvidia=1
            ;;
    esac
done

# Dedicated mode:
# - BIOS MUX switch set to Discrete (AMD iGPU unpowered / absent from PCI bus)
# - OR EnvyControl set to 'nvidia' (/etc/X11/xorg.conf exists)
if [ "$has_amd" -eq 0 ] || [ -f /etc/X11/xorg.conf ]; then
    echo "LIBVA_DRIVER_NAME=nvidia"
    echo "__GLX_VENDOR_LIBRARY_NAME=nvidia"
    # Unrestricted Vulkan loader allows games and apps to natively find NVIDIA ICD
    exit 0
fi

# Hybrid mode:
# - Both AMD APU and NVIDIA dGPU present on PCI bus
if [ "$has_amd" -eq 1 ] && [ "$has_nvidia" -eq 1 ]; then
    # Pin default Vulkan to AMD APU so desktop/background apps do not wake dGPU
    # High-performance games use 'prime-run <command>' to offload to NVIDIA
    echo "VK_DRIVER_FILES=/usr/share/vulkan/icd.d/radeon_icd.x86_64.json"
    exit 0
fi

# Integrated mode:
# - Only AMD APU present (NVIDIA disabled/removed)
# Pure Mesa defaults apply; no overrides needed.
