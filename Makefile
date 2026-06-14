HOST ?= $(shell hostname)
NIX  ?= nix
PIS  := pik8s1 pik8s2 pik8s3 pik8s4 pik8s5 pik8s6

# The default location of the weird sd-card adapter I have
DISK ?= /dev/sdi

build:
	$(NIX) build .#nixosConfigurations.${HOST}.config.system.build.toplevel

hades: HOST := hades
hades: build

agreus: HOST := agreus
agreus: build

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
	$(NIX) build --out-link $@ .#nixosConfigurations.$*.config.system.build.images.sd-card

${PIS:%=%-flash}: %-flash: bin/%-sd-card.img
	sudo dd if=$< of=$(DISK) bs=4M status=progress conv=fsync

.PHONY: build hades agreus check format fmt update system sd-images \
        pik8s1-sd pik8s2-sd pik8s3-sd pik8s4-sd pik8s5-sd pik8s6-sd \
        pik8s1-flash pik8s2-flash pik8s3-flash pik8s4-flash pik8s5-flash pik8s6-flash
