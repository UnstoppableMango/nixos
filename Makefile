HOST ?= $(shell hostname)
NIX  ?= nix
PIS  := pik8s1 pik8s2 pik8s3 pik8s4 pik8s5 pik8s6

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

${PIS:%=%-install}: %-install:
	clan machines install $*

.kube/rosequartz/config:
	@mkdir -p ${@D}
	$(NIX) run .#rosequartz-kubeconfig $@

.PHONY: build hades agreus check format fmt update system \
        pik8s1-install pik8s2-install pik8s3-install \
        pik8s4-install pik8s5-install pik8s6-install \
        rosequartz-kubeconfig
