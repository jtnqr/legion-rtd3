#define _GNU_SOURCE
#include <dlfcn.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <dirent.h>
#include <stdio.h>

/*
 * Dynamic interceptor for libnvidia-ml.so
 *
 * Prevents monitoring tools (nvtop, btop) from waking the NVIDIA dGPU out of
 * runtime D3cold (suspended) state. When the dGPU is asleep, dlopen() calls
 * matching 'nvidia-ml' return NULL, signaling that NVML is not available.
 *
 * When the dGPU is actively running a workload or when explicitly requested
 * via __NV_PRIME_RENDER_OFFLOAD=1 or FORCE_NVIDIA=1, real_dlopen() proceeds normally.
 */

static int is_nvidia_sleeping(void) {
    const char *prime = getenv("__NV_PRIME_RENDER_OFFLOAD");
    const char *force = getenv("FORCE_NVIDIA");
    if ((prime && prime[0] == '1') || (force && force[0] == '1')) {
        return 0;
    }

    DIR *dir = opendir("/sys/bus/pci/devices");
    if (!dir) return 0;

    struct dirent *entry;
    char path[512];
    char buf[16];

    while ((entry = readdir(dir)) != NULL) {
        if (entry->d_name[0] == '.') continue;

        snprintf(path, sizeof(path), "/sys/bus/pci/devices/%s/vendor", entry->d_name);
        int fd = open(path, O_RDONLY);
        if (fd < 0) continue;
        ssize_t n = read(fd, buf, sizeof(buf) - 1);
        close(fd);
        if (n <= 0) continue;
        buf[n] = '\0';

        if (strncmp(buf, "0x10de", 6) == 0) {
            snprintf(path, sizeof(path), "/sys/bus/pci/devices/%s/class", entry->d_name);
            fd = open(path, O_RDONLY);
            if (fd >= 0) {
                n = read(fd, buf, sizeof(buf) - 1);
                close(fd);
                if (n > 0) {
                    buf[n] = '\0';
                    // Class 0x0300 (VGA) or 0x0302 (3D controller)
                    if (strncmp(buf, "0x0300", 6) == 0 || strncmp(buf, "0x0302", 6) == 0) {
                        snprintf(path, sizeof(path), "/sys/bus/pci/devices/%s/power/runtime_status", entry->d_name);
                        fd = open(path, O_RDONLY);
                        if (fd >= 0) {
                            n = read(fd, buf, sizeof(buf) - 1);
                            close(fd);
                            closedir(dir);
                            return (n > 0 && strncmp(buf, "suspended", 9) == 0);
                        }
                    }
                }
            }
        }
    }
    closedir(dir);
    return 0;
}

void *dlopen(const char *filename, int flags) {
    static void *(*real_dlopen)(const char *, int) = NULL;
    if (!real_dlopen) {
        real_dlopen = dlsym(RTLD_NEXT, "dlopen");
    }

    if (filename && strstr(filename, "nvidia-ml")) {
        if (is_nvidia_sleeping()) {
            return NULL;
        }
    }

    return real_dlopen(filename, flags);
}
