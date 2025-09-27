HOST ?= $(shell hostname)
NIX  ?= nix

build:
	$(NIX) build .#nixosConfigurations.${HOST}.config.system.build.toplevel

check:
	$(NIX) flake check

format fmt:
	$(NIX) fmt

update:
	$(NIX) flake update

system:
	sudo nix flake update --flake /etc/nixos
	sudo nixos-rebuild switch --flake /etc/nixos
