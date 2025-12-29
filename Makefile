HOST ?= $(shell hostname)
NIX  ?= nix

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
