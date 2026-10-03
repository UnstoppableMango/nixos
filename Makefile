HOST ?= $(shell hostname)
NIX  ?= nix
PIS  := pik8s1 pik8s2 pik8s3 pik8s4 pik8s5 pik8s6
X86  := hades agreus apollo castor gaea iris pollux zeus

# SD images build against the nixos-hardware that flashed pik8s4-6. Later
# revisions replace the sd-image firmware partition with one that ships no
# kernel unless U-Boot staging is enabled, and with it enabled U-Boot fails
# to read the SD card. Only the image is pinned; deploys use the locked input.
PI_NIXOS_HARDWARE ?= github:NixOS/nixos-hardware/a9cf7546a938c737b079e738de73934a13de9784

# The default location of the weird sd-card adapter I have
DISK ?= /dev/sdi

build:
	$(NIX) build .#nixosConfigurations.${HOST}.config.system.build.toplevel

hades: HOST := hades
hades: build

agreus: HOST := agreus
agreus: build

pollux: HOST := pollux
pollux: build

castor: HOST := castor
castor: build

zeus: HOST := zeus
zeus: build

gaea: HOST := gaea
gaea: build

iris: HOST := iris
iris: build

check:
	$(NIX) flake check

format fmt:
	$(NIX) fmt

update:
	$(NIX) flake update

system:
	sudo nix flake update --flake /etc/nixos
	sudo nixos-rebuild switch --flake /etc/nixos --cores 12

bin:
	mkdir -p bin

sd-images: ${PIS:%=%-sd}

${PIS:%=%-sd}: %-sd: bin/%-sd-card.img

bin/%-sd-card.img: bin/%-sd-card | bin
	unzstd -o $@ $$(find -L $< -name '*.img.zst')

.SECONDARY: ${PIS:%=%-sd-card}
bin/%-sd-card: | bin
	$(NIX) build --out-link $@ --override-input nixos-hardware $(PI_NIXOS_HARDWARE) \
		.#nixosConfigurations.$*.config.system.build.images.sd-card

# Generic installer with no machine config. See installer-iso in flake.nix.
iso: bin/installer.iso

# A host's own config on an installer ISO, services included.
${X86:%=%-iso}: %-iso: bin/%.iso

bin/%.iso: bin/%-iso | bin
	ln -sf $$(readlink -f $$(find -L $< -name '*.iso')) $@

.SECONDARY: bin/installer-iso ${X86:%=bin/%-iso}
bin/installer-iso: | bin
	$(NIX) build --out-link $@ .#installer-iso

bin/%-iso: | bin
	$(NIX) build --out-link $@ .#nixosConfigurations.$*.config.system.build.images.iso-installer

${PIS:%=%-flash}: %-flash: bin/%-sd-card.img
	sudo dd if=$< of=$(DISK) bs=4M status=progress conv=fsync

.PHONY: build hades agreus pollux castor zeus gaea iris check format fmt update system sd-images \
        pik8s1-sd pik8s2-sd pik8s3-sd pik8s4-sd pik8s5-sd pik8s6-sd \
        pik8s1-flash pik8s2-flash pik8s3-flash pik8s4-flash pik8s5-flash pik8s6-flash \
        iso ${X86:%=%-iso}
