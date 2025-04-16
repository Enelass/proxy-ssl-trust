# Proxy_SSL_Trust

## Description

The purpose of this suite of scripts is to fix certificate trust issues where clients (CLI mostly but also a few GUIs) fail to connect as they do not trust Internal Certificate Authorities found in KeychainAccess. This script invokes other scripts to detect proxy settings and create persistent connectivity for the current user. It also supports a variety of switches for advanced troubleshooting.

## Author

- Florian Bidabe

## Version

- **Current Version**: 1.7
- **Initial Release Date**: 19-Sep-2024
- **Last Release Date**: 30-Mar-2025

## Usage

This script is designed for macOS systems and requires `zsh` to function. Various switches have been provided to perform specific tasks:

### General Usage

```zsh
./Proxy_SSL_Trust.sh [OPTION]...
```

### Options

- `--help, -h`: Show the help menu.
- `--version, -v`: Show the version information.
- `--list, -l`: List all the signing Root CAs from the macOS Keychain Access. This is useful to check what Root CAs are supplied or performing SSL Inspection.
- `--scan, -s`: Scan for PEM Certificate Stores on the system without patching. Useful to locate software certificate stores.
- `--var`: Set default shell environment variable to a known PEM Certificate Store containing internal and Public Root CA. Useful for quick fixes in user context.
- `--var_uninstall`: Revert any changes made by `--var`, restoring the original state.
- `--patch, -p`: Patch known PEM Certificate Stores (requires `--scan`). Useful for patching known certificate stores (not recommended).
- `--patch_uninstall`: Revert any changes made by `--patch`, restoring the original state.
- `--proxy`: Set up proxy and PAC file & install Alpaca as a daemon.
- `--proxy_uninstall`: Uninstall proxy and PAC settings.

### Examples

1. **Show Help Menu**:
    ```zsh
    ./Proxy_SSL_Trust.sh --help
    ```

2. **Show Version Information**:
    ```zsh
    ./Proxy_SSL_Trust.sh --version
    ```

3. **List Root CAs from Keychain Access**:
    ```zsh
    ./Proxy_SSL_Trust.sh --list
    ```

4. **Scan for PEM Certificate Stores**:
    ```zsh
    ./Proxy_SSL_Trust.sh --scan
    ```

5. **Set Environment Variable for Certificate Store**:
    ```zsh
    ./Proxy_SSL_Trust.sh --var
    ```

6. **Revert Environment Variable Settings**:
    ```zsh
    ./Proxy_SSL_Trust.sh --var_uninstall
    ```

7. **Patch Known PEM Certificate Stores**:
    ```zsh
    ./Proxy_SSL_Trust.sh --patch
    ```

8. **Revert PEM Patching**:
    ```zsh
    ./Proxy_SSL_Trust.sh --patch_uninstall
    ```

9. **Set up Proxy and PAC File**:
    ```zsh
    ./Proxy_SSL_Trust.sh --proxy
    ```

10. **Uninstall Proxy Settings**:
    ```zsh
    ./Proxy_SSL_Trust.sh --proxy_uninstall
    ```

## Notes

- Ensure you have the necessary permissions to run this script as it may require elevated privileges for certain operations.
- The script checks for the presence of critical tools like `Homebrew` and `curl`. If not found, the script attempts to install them.
- The script logs its operations and caps the log file at 10,000 lines to prevent overgrowth.

## Logging

Log files are created in `/tmp` directory with the name `Proxy_SSL_Trust.log`. Ensure you have the necessary permissions to write logs in `/tmp`.

## Contact

For any issues or support, you can reach out to the author at florian@photonsec.com.au.

GitHub Repository: [github.com/Enelass](https://github.com/Enelass)

---