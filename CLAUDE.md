# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**proxy-ssl-trust** is a macOS utility suite that resolves certificate trust issues for CLI tools by managing proxy settings and internal Certificate Authorities. It runs on macOS with Zsh shell and uses Homebrew for package management.

The project consists of a main orchestrator script that coordinates several independent modules for handling proxy configuration, SSL certificate management, and system integration.

## Architecture

### High-Level Design

The system has three main functional areas:

1. **Proxy Management** (`/proxy` directory): Detects and configures network proxy settings, including PAC file processing and Alpaca daemon setup
2. **SSL/Certificate Management** (`/SSL` directory): Manages PEM certificate stores, scans for certificates, patches them with internal CAs, and extracts certs from Keychain
3. **Shared Utilities** (`/lib` directory): Provides color output, logging, spinner animations, and user context detection used by all modules

### Module Relationships

- **proxy_ssl_trust.sh** (main orchestrator): Entry point that parses command-line flags and executes one of seven operational modes
- **Modes** set variables that trigger specific workflows (e.g., `proxy=1` triggers proxy setup, `pempatch=1` triggers certificate patching)
- **SSL modules** are often chained together (e.g., `--scan` must run before `--patch` can work)
- **Shared utilities** are sourced by all modules via `source "$script_dir/lib/stderr_stdout_syntax.sh"`

### Key Modules

| Module | Purpose |
|--------|---------|
| `SSL/PEM_Scan.sh` | Scans system for PEM certificate stores without modifying them |
| `SSL/PEM_Patch.sh` | Patches PEM stores with internal CAs after scanning |
| `SSL/PEM_Var.sh` | Sets shell environment variables to use a custom certificate store |
| `SSL/Keychain_InternalCAs.sh` | Extracts internal CA certificates from macOS Keychain Access |
| `proxy/AlpacaSetup.sh` | Installs and configures Alpaca as a daemon for proxy management |
| `proxy/pac_proxy_extract.sh` | Parses PAC files to extract proxy addresses |
| `lib/stderr_stdout_syntax.sh` | Provides colored output, logging, and utility functions |

### Module Dependencies

- SSL modules depend on `stderr_stdout_syntax.sh` for logging and output formatting
- Proxy modules depend on `stderr_stdout_syntax.sh` and utility functions from `interfaces.sh`
- `PEM_Check.sh` is called by multiple modules to validate PEM file integrity
- The main script coordinates execution through switch variables and conditionals

## Common Development Tasks

### Running the Main Script

```zsh
# Default mode (proxy setup)
./proxy_ssl_trust.sh

# With specific option
./proxy_ssl_trust.sh --scan
./proxy_ssl_trust.sh --patch
./proxy_ssl_trust.sh --help
```

### Testing Individual Modules

```zsh
# Test SSL scanning directly
./SSL/PEM_Scan.sh

# Test certificate extraction from Keychain
./SSL/Keychain_InternalCAs.sh

# Test proxy configuration
./proxy/AlpacaSetup.sh

# Test PAC file parsing
./proxy/pac_proxy_extract.sh
```

### Logging and Debugging

- **Log file location**: `/tmp/Proxy_SSL_Trust.log` (created during execution)
- **Log output functions**: Available from `lib/stderr_stdout_syntax.sh`
  - `log "message"` - Standard log
  - `logI "message"` - Info (blue)
  - `logW "message"` - Warning (orange)
  - `logS "message"` - Success (green)
  - `logE "message"` - Error (red)
- **Verbosity control**: `quiet` function suppresses output, `unquiet` restores it

### Understanding Execution Flow

The main script uses a pattern of setting switch variables, then executing conditional blocks:

```zsh
# User runs: ./proxy_ssl_trust.sh --scan
scan() { pemscan=1 }  # This sets the switch variable

# Later in runtime section:
if [[ $pemscan -eq 1 ]]; then
    # Execute scan operation
fi
```

This allows chaining operations (e.g., `--scan` creates data that `--patch` consumes).

## Code Patterns

### Shared Utility Sourcing

All modules source the shared utilities at runtime:

```zsh
source "$script_dir/lib/stderr_stdout_syntax.sh"
```

The `teefile` variable must be set before sourcing to control log location.

### Color Output Constants

Available after sourcing `stderr_stdout_syntax.sh`:
- `RED`, `GREEN`, `ORANGE`, `PURPLE`, `PINK`, `BLUEW`, `GREENW`, `NC` (no color)

### User Context Detection

Functions from `stderr_stdout_syntax.sh`:
- `default_user` - Detects current user even if running as root/sudo
- `shell_config` - Identifies shell config file path (e.g., `~/.zshrc`)

## Important Implementation Details

### Uninstall Operations

Each major operation (--proxy, --scan, --patch, --var) has a corresponding `--*_uninstall` flag that:
1. Restores original files from backups
2. Removes generated files
3. Reverts shell configuration changes

Store backup paths and original state carefully to enable reliable uninstall.

### PEM Certificate Store Patching

The patching workflow:
1. `PEM_Scan.sh` identifies certificate stores system-wide
2. `Keychain_InternalCAs.sh` extracts internal CAs from Keychain
3. `PEM_Check.sh` validates PEM file format
4. `PEM_Patch.sh` appends internal CAs to identified stores
5. Backups are maintained to support uninstall

### Proxy Configuration

The proxy setup workflow:
1. Detect proxy settings from system configuration
2. Parse PAC files to extract actual proxy addresses
3. Install Alpaca daemon to manage proxy connections
4. Configure shell environment variables for proxy usage

### Interrupt Handling

Signals are trapped to ensure clean shutdown:
```zsh
trap 'stop_spinner_sigint; play_sigint > /dev/null 2>&1' SIGINT
trap 'stop_spinner; play_exit > /dev/null 2>&1' EXIT
```

Ensure any background processes spawned are terminated properly.

## File Locations and Conventions

- **Main entry point**: `proxy_ssl_trust.sh` (not `Proxy_SSL_Trust.sh` - lowercase in code)
- **Configuration backups**: Created in temp directories, referenced in uninstall operations
- **Log file**: `/tmp/Proxy_SSL_Trust.log`
- **User shell config**: Detected dynamically (typically `~/.zshrc` or `~/.bash_profile`)
- **Temp storage**: `/tmp/` directory for intermediate files

## Known Limitations and Gotchas

- **macOS only**: All scripts assume macOS with `zsh` shell and `security` framework
- **Homebrew requirement**: Package installation relies on Homebrew
- **Root/sudo context**: Scripts detect and handle running as root, but some operations may require appropriate permissions
- **PAC file parsing**: Limited to standard PAC syntax; complex or custom PAC files may not parse correctly
- **Certificate store locations**: New certificate stores not in the predefined list won't be detected by `PEM_Scan.sh`

## Testing and Validation

- Test SSL modules in isolation before running full proxy setup
- Use `--scan` (read-only) before `--patch` to preview changes
- Always test `--*_uninstall` operations to ensure backup/restore works correctly
- Check `/tmp/Proxy_SSL_Trust.log` for detailed execution logs
- Verify Alpaca daemon status after proxy setup: `launchctl list | grep alpaca`
