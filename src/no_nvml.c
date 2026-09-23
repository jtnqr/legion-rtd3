#define _GNU_SOURCE
#include <dlfcn.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <dirent.h>
#include <stdio.h>

#define NVML_SUCCESS 0
#define NVML_ERROR_DRIVER_NOT_LOADED 9

/*
 * Dynamic interceptor and symbol stub for libnvidia-ml.so
 *
 * Prevents monitoring tools (nvtop, btop) from waking the NVIDIA dGPU out of
 * runtime D3cold (suspended) state. When the dGPU is asleep:
 * 1. dlopen() calls matching 'nvidia-ml' return NULL.
 * 2. Directly linked nvmlInit* calls return NVML_ERROR_DRIVER_NOT_LOADED.
 *
 * When the dGPU is actively running a workload or when explicitly requested
 * via __NV_PRIME_RENDER_OFFLOAD=1 or FORCE_NVIDIA=1, native behavior proceeds.
 */

static char cached_pci_status_path[512] = {0};

static int find_nvidia_status_path(char *out_path, size_t out_len) {
    if (cached_pci_status_path[0] != '\0') {
        strncpy(out_path, cached_pci_status_path, out_len);
        return 1;
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
                    if (strncmp(buf, "0x0300", 6) == 0 || strncmp(buf, "0x0302", 6) == 0) {
                        snprintf(cached_pci_status_path, sizeof(cached_pci_status_path),
                                 "/sys/bus/pci/devices/%s/power/runtime_status", entry->d_name);
                        strncpy(out_path, cached_pci_status_path, out_len);
                        closedir(dir);
                        return 1;
                    }
                }
            }
        }
    }
    closedir(dir);
    return 0;
}

static int is_nvidia_sleeping(void) {
    const char *prime = getenv("__NV_PRIME_RENDER_OFFLOAD");
    const char *force = getenv("FORCE_NVIDIA");
    if ((prime && prime[0] == '1') || (force && force[0] == '1')) {
        return 0;
    }

    char status_path[512];
    if (!find_nvidia_status_path(status_path, sizeof(status_path))) {
        return 0;
    }

    int fd = open(status_path, O_RDONLY);
    if (fd < 0) return 0;

    char buf[16] = {0};
    ssize_t n = read(fd, buf, sizeof(buf) - 1);
    close(fd);

    return (n > 0 && strncmp(buf, "suspended", 9) == 0);
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

int nvmlInit_v2(void) {
    if (is_nvidia_sleeping()) return NVML_ERROR_DRIVER_NOT_LOADED;
    static int (*real_init)(void) = NULL;
    if (!real_init) real_init = dlsym(RTLD_NEXT, "nvmlInit_v2");
    return real_init ? real_init() : NVML_ERROR_DRIVER_NOT_LOADED;
}

int nvmlInit(void) {
    if (is_nvidia_sleeping()) return NVML_ERROR_DRIVER_NOT_LOADED;
    static int (*real_init)(void) = NULL;
    if (!real_init) real_init = dlsym(RTLD_NEXT, "nvmlInit");
    return real_init ? real_init() : NVML_ERROR_DRIVER_NOT_LOADED;
}
