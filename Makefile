_ != mkdir -p .make

SYSTEM_CONFIG := $(wildcard ./system/*.nix)

build: result
check: .make/nix-flake-check

result: flake.nix ${SYSTEM_CONFIG}
	nix build .#

flake.lock: flake.nix ${SYSTEM_CONFIG}
	nix flake update

.make/nix-flake-check: flake.nix
	nix flake check
	@touch $@
