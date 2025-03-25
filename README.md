# CATrust.sh
This script aims to save days if not weeks of productivity loss due to the lengthy troubleshooting of certificate trust and proxy issues. It is designed to fix certificate trust issues where any client fails to connect as it does not trust MacOS Certificate Authorities found in the Keychain (System Store) issued internally in the Group. The script adds the Base64 Root certificate authorities to the various client certificate store conventionally named (cacert.pem).

## Description

The purpose of this script is to resolve certificate trust issues by adding Base64 Root certificate authorities to the client certificate store (cacert.pem). This addresses situations where clients fail to connect due to a lack of trust in the Group's internal Certificate Authorities typically found in the Keychain (MacOS System Certificate Store).

## Requirements

- CommBank macOS SOE
- Homebrew
- Local admin

## Usage

1. Make the script executable using the command `chmod +x CATrust.sh`.
2. Run the script using the command `./CATrust.sh`.

## Screenshot

![Alt Text](assets/screenshot.png)

## Functions

- **Logging**: Logs messages to the console and a log file in /tmp

- **List Enrichment**: Enriches the list of cacert.pem files with additional information such as the application name, file path, magic byte, and SHA1 signature.

- **Optimized Runtime**: Each `cacert.pem` file is only patched if its SHA1 signature has changed. The Base64 Internal Root CA is only added if it is not already present in the certificate store. The script uses both GNU `find` and `locate` for efficient file searching. `locate` is very fast but cannot scan `/Users` directories. `find` is slower but can search all files, complying with POSIX file permissions and macOS ACLs.

- **Security Checks**: Each modified file will have backups (no more than 4 timestamped backups + the original file). The script will exit if anything goes wrong.

- **Certificate Addition**: Adds the Base64 internal certificates to various local certificate stores (cacert.pem) to avoid certificate trust issues.

## High-Level Workflow

1. **Check Requirements**: Ensures the script is running with root privileges and verifies system requirements.
2. **Search for cacert.pem Files**: Uses `locate` and `find` to search for cacert.pem files on the system.
3. **Maintain Database**: Maintains a database of cacert.pem files with integrity checks.
4. **Process cacert.pem Files**: Processes each cacert.pem file one by one, checking if it exists in the previous database and if the SHA1 signature has changed. If the SHA1 signature has changed, the script patches the cacert.pem file.

This script aims to save days if not weeks of productivity loss due to the lengthy troubleshooting of certificate trust and proxy issues.


## License

This script is licensed under a license agreement. Please refer to the [LICENSE](LICENSE.md) file for the full terms and conditions.


## Support

For support, reach out to Florian Bidabe or SecurityGenAI@cba.com.au and forward your log file located at `/tmp/CATrustDaemon.log`.

## Author

- **Florian Bidabe**