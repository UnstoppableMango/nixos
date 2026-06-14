HOST ?= $(shell hostname)
NIX  ?= nix
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

agreus-system:
	$(NIX) run github:nix-community/nixos-anywhere -- \
	--flake '.#agreus' --generate-hardware-config nixos-facter ./hosts/agreus/facter.json \
	root@192.168.1.237

sd-images: pik8s1-sd pik8s2-sd pik8s3-sd pik8s4-sd pik8s5-sd pik8s6-sd

%-sd:
	clan machines build $* --format sd-card

pik8s1-flash pik8s2-flash pik8s3-flash pik8s4-flash pik8s5-flash pik8s6-flash: %-flash:
	# SOPS_AGE_KEY_FILE: sudo strips the user environment, so root can't find the age key to decrypt vars
	sudo SOPS_AGE_KEY_FILE=$(HOME)/.config/sops/age/keys.txt \
	  clan flash write \
	  --flake $(CURDIR) \
	  --ssh-pubkey $(HOME)/.ssh/id_ed25519.pub \
	  --keymap us \
	  --language en_US.UTF-8 \
	  --disk mmcblk0 $(DISK) \
	  --yes \
	  $*

.PHONY: build hades agreus check format fmt update system agreus-system sd-images \
        pik8s1-sd pik8s2-sd pik8s3-sd pik8s4-sd pik8s5-sd pik8s6-sd \
        pik8s1-flash pik8s2-flash pik8s3-flash pik8s4-flash pik8s5-flash pik8s6-flash
