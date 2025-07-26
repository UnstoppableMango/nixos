_ != mkdir -p .make

SYSTEM_CONFIG := $(wildcard ./system/*.nix)

PULUMI ?= bin/pulumi

build: result
check: .make/nix-flake-check
iso: result/iso/nixos.iso

CMD ?= up
.PHONY: dev
dev: iso | $(PULUMI)
	$(PULUMI) --cwd dev ${CMD}

result: flake.nix ${SYSTEM_CONFIG}
	nix build .#nixosConfigurations.hades.config.system.build.toplevel

result/iso/nixos.iso: flake.nix ${SYSTEM_CONFIG}
	nix build .#hades-iso

flake.lock: flake.nix ${SYSTEM_CONFIG}
	nix flake update

bin/pulumi: .versions/pulumi
	curl -fsSL https://get.pulumi.com | sh -s -- --install-root ${CURDIR} --version $(shell cat $<) --no-edit-path

.make/nix-flake-check: flake.nix
	nix flake check
	@touch $@
