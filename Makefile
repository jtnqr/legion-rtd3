CC ?= gcc
CFLAGS ?= -O2 -Wall -Wextra
PREFIX ?= /usr/local
SYSCONFDIR ?= /etc

all: build

build: bin/libno_nvml.so

bin/libno_nvml.so: src/no_nvml.c
	mkdir -p bin
	$(CC) $(CFLAGS) -shared -fPIC -o bin/libno_nvml.so src/no_nvml.c -ldl

clean:
	rm -f bin/libno_nvml.so

install: build
	# User-space binaries and interceptor
	install -Dm755 bin/libno_nvml.so $(DESTDIR)$(PREFIX)/lib/libno_nvml.so
	install -Dm755 bin/gpu-guard $(DESTDIR)$(PREFIX)/bin/gpu-guard
	install -Dm755 bin/prime-run $(DESTDIR)$(PREFIX)/bin/prime-run
	install -Dm755 bin/legion-rtd3 $(DESTDIR)$(PREFIX)/bin/legion-rtd3
	ln -sf gpu-guard $(DESTDIR)$(PREFIX)/bin/nvtop
	ln -sf gpu-guard $(DESTDIR)$(PREFIX)/bin/btop

	# System driver configs & environment generators
	install -Dm755 etc/systemd/user-environment-generators/10-gpu-mode.sh $(DESTDIR)$(SYSCONFDIR)/systemd/user-environment-generators/10-gpu-mode.sh

	# TLP display power settings
	install -Dm644 etc/tlp.d/98-amdgpu-abm.conf $(DESTDIR)$(SYSCONFDIR)/tlp.d/98-amdgpu-abm.conf

	# Udev power management rules
	install -Dm644 etc/udev/rules.d/61-mutter-primary-gpu.rules $(DESTDIR)$(SYSCONFDIR)/udev/rules.d/61-mutter-primary-gpu.rules
	install -Dm644 etc/udev/rules.d/80-nvidia-pm.rules $(DESTDIR)$(SYSCONFDIR)/udev/rules.d/80-nvidia-pm.rules
	install -Dm644 etc/udev/rules.d/81-nvidia-hotplug-pm.rules $(DESTDIR)$(SYSCONFDIR)/udev/rules.d/81-nvidia-hotplug-pm.rules
	install -Dm644 etc/udev/rules.d/82-dock-dgpu-wake.rules $(DESTDIR)$(SYSCONFDIR)/udev/rules.d/82-dock-dgpu-wake.rules

	# Desktop overrides
	install -Dm644 desktop/steam.desktop $(DESTDIR)$(PREFIX)/share/applications/steam.desktop

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/lib/libno_nvml.so
	rm -f $(DESTDIR)$(PREFIX)/bin/gpu-guard
	rm -f $(DESTDIR)$(PREFIX)/bin/prime-run
	rm -f $(DESTDIR)$(PREFIX)/bin/legion-rtd3
	rm -f $(DESTDIR)$(PREFIX)/bin/nvtop
	rm -f $(DESTDIR)$(PREFIX)/bin/btop
	rm -f $(DESTDIR)$(SYSCONFDIR)/systemd/user-environment-generators/10-gpu-mode.sh
	rm -f $(DESTDIR)$(SYSCONFDIR)/tlp.d/98-amdgpu-abm.conf
	rm -f $(DESTDIR)$(SYSCONFDIR)/udev/rules.d/61-mutter-primary-gpu.rules
	rm -f $(DESTDIR)$(SYSCONFDIR)/udev/rules.d/80-nvidia-pm.rules
	rm -f $(DESTDIR)$(SYSCONFDIR)/udev/rules.d/81-nvidia-hotplug-pm.rules
	rm -f $(DESTDIR)$(SYSCONFDIR)/udev/rules.d/82-dock-dgpu-wake.rules
	rm -f $(DESTDIR)$(PREFIX)/share/applications/steam.desktop

.PHONY: all build clean install uninstall
