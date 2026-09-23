#!/bin/sh
# Dynamic GPU environment generator for systemd user session
# Supports AMD (Legion) and Intel (Legion Intel / Legion "i" variants)

has_igpu=0
has_nvidia=0
igpu_vendor=""

# Detect display-capable GPUs from PCI class 03xxxx (VGA / 3D / Display)
for dev in /sys/bus/pci/devices/*; do
    [ -f "$dev/class" ] || continue
    class=$(cat "$dev/class" 2>/dev/null || true)
    case "$class" in
        0x0300*|0x0302*|0x0380*)
            vendor=$(cat "$dev/vendor" 2>/dev/null || true)
            case "$vendor" in
                0x1002) # AMD
                    has_igpu=1
                    igpu_vendor="amd"
                    ;;
                0x8086) # Intel
                    has_igpu=1
                    igpu_vendor="intel"
                    ;;
                0x10de) # NVIDIA
                    has_nvidia=1
                    ;;
            esac
            ;;
    esac
done

# Dedicated mode:
# - BIOS MUX switch set to Discrete (iGPU unpowered / absent from PCI bus)
# - OR EnvyControl set to 'nvidia' (/etc/X11/xorg.conf exists)
if [ "$has_igpu" -eq 0 ] || [ -f /etc/X11/xorg.conf ]; then
    echo "LIBVA_DRIVER_NAME=nvidia"
    echo "__GLX_VENDOR_LIBRARY_NAME=nvidia"
    exit 0
fi

# Hybrid mode:
# - Both iGPU and NVIDIA dGPU present on PCI bus
if [ "$has_igpu" -eq 1 ] && [ "$has_nvidia" -eq 1 ]; then
    if [ "$igpu_vendor" = "amd" ] && [ -f /usr/share/vulkan/icd.d/radeon_icd.x86_64.json ]; then
        echo "VK_DRIVER_FILES=/usr/share/vulkan/icd.d/radeon_icd.x86_64.json"
    elif [ "$igpu_vendor" = "intel" ] && [ -f /usr/share/vulkan/icd.d/intel_icd.x86_64.json ]; then
        echo "VK_DRIVER_FILES=/usr/share/vulkan/icd.d/intel_icd.x86_64.json"
    fi
    exit 0
fi

# Integrated mode:
# - Only iGPU present. Pure Mesa defaults apply; no overrides needed.
