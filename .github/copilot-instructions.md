# GitHub Copilot Instructions for NixOS Configuration

This repository contains UnstoppableMango's personal NixOS configurations using Nix flakes.

## Repository Structure

- `flake.nix` - Main flake configuration with inputs and outputs
- `hosts/` - Host-specific configurations (hades, agreus)
- `users/` - User-specific configurations (erik)
- `desktops/` - Desktop environment configurations (GNOME)
- `hardware/` - Hardware-specific configurations (nvidia)
- `toolchain/` - Development toolchain configurations
- `shells/` - Shell configurations (ssh)

## Code Style and Conventions

### Formatting
- Use `nix fmt` to format Nix files (uses nixfmt as configured in flake.nix)
- Nix files use space indentation (see .editorconfig; nixfmt determines specific size)
- YAML files use 2-space indentation
- Other files use tabs (see .editorconfig)
- Always include final newline and trim trailing whitespace

### Nix Code Style
- Follow the flake-parts pattern used throughout the repository
- Use `inputs@{ ... }` pattern for accessing flake inputs
- Keep module imports organized with `imports = [ ... ];`
- Use `with pkgs;` when referencing multiple packages
- Enable experimental features: `nix-command` and `flakes`

### Module Structure
- Each module should export both `flake.modules.nixos.*` and `flake.modules.homeManager.*` when applicable
- Use `self.modules.*` for internal module references
- Follow the pattern seen in `users/erik/default.nix` for module organization

## Building and Testing

### Commands
- `nix build .#nixosConfigurations.<HOST>.config.system.build.toplevel` - Build a host configuration
- `nix flake check` - Run flake checks (CI uses `--all-systems` flag)
- `nix fmt` - Format all Nix files
- `make build` - Build the configuration for the current hostname
- `make check` - Run flake checks (without --all-systems)
- `make format` or `make fmt` - Format Nix files
- `make update` - Update flake inputs

### Host-specific builds
- `make hades` - Build hades configuration
- `make agreus` - Build agreus configuration

## Dependencies and Inputs

### Key Flake Inputs
- `nixpkgs` - Using nixos-unstable channel
- `home-manager` - User environment management
- `nixos-hardware` - Hardware-specific configurations
- `flake-parts` - Modular flake framework
- `nixos-anywhere` - Remote NixOS installation
- `nixvim` - Neovim configuration
- `disko` - Declarative disk partitioning
- `dotfiles` - Personal dotfiles repository
- `treefmt-nix` - Multi-formatter configuration

### Overlays and Caches
- Custom cachix cache: `unstoppablemango.cachix.org`
- Additional caches: nix-community, zed, garnix
- Dotfiles overlay applied in erik's configuration

## Special Considerations

### Hardware
- AMD GPU support via amdgpu kernel module
- NVIDIA hardware configurations available in hardware/nvidia/
- BTRFS filesystem with zstd compression
- Automatic BTRFS scrubbing configured weekly

### Security
- GPG agent enabled with SSH support
- User erik signs commits with GPG key 264283BBFDC491BC
- Custom CA certificates for thecluster.lan domain
- Firewall disabled by default

### Virtualization
- Docker with BTRFS storage driver
- Docker rootless mode enabled
- KVM/libvirt for VM management
- User erik has libvirtd/libvirt group access

### User Environment
- Default shell: bash (system), zsh (user erik)
- direnv enabled with nix-direnv integration
- home-manager manages user-specific configurations
- Auto-login enabled for user erik

## Development Tools

### Installed Packages
- Build tools: gcc, clang, cmake, ninja
- Languages: python3, rustup, rbenv
- CLI tools: git, kubectl, kind, ripgrep, bat, tmux
- Editors: vim, nano, micro, vscode, zed
- Shells: bash, zsh

### IDE Configuration
- VS Code settings in .vscode/settings.json
- Nix IDE extension recommended
- nil language server configured
- nixfmt as formatter

## CI/CD

### GitHub Actions
- Workflow: `.github/workflows/ci.yml`
- Runs on: nixos-runners
- Checks: `nix flake check --all-systems`
- Caching: Cachix (unstoppablemango)
- Note: hades build disabled in CI (too large)

## Best Practices

1. **Always run `nix flake check` before committing**
2. **Use `nix fmt` to format code**
3. **Keep module structure consistent with existing patterns**
4. **Follow flake-parts conventions for organizing outputs**
5. **Pin dependencies using flake.lock (committed to repo)**
6. **Test configurations locally before deploying to hosts**
7. **Use descriptive commit messages**
8. **Keep host configurations in separate directories**
9. **Document any non-obvious configuration choices**
10. **Prefer declarative configuration over imperative commands**

## Common Tasks

### Adding a new package to a host
Add to `environment.systemPackages` in the host's configuration.nix

### Adding a user package
Add to the user's home.packages in users/<username>/default.nix

### Adding a new host
1. Create hosts/<hostname>/configuration.nix
2. Create hosts/<hostname>/hardware-configuration.nix
3. Create hosts/<hostname>/default.nix
4. Add to hosts/default.nix imports
5. Add make target in Makefile

### Updating dependencies
Run `make update` or `nix flake update`

### Remote deployment (agreus example)
Use nixos-anywhere via the make target: `make agreus-system`
