# Jamia Wi-Fi Auto-Login

A lightweight PowerShell script that automates login to **Jamia Millia Islamia's captive-portal Wi-Fi** on Windows. Once configured, it detects the login portal and authenticates automatically, so you don't have to enter your credentials every time the connection drops or the network reconnects.

Built with PowerShell, the script runs without Python, Node.js, or any external dependencies.

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)
![Windows](https://img.shields.io/badge/Windows-10%2F11-green)
![License](https://img.shields.io/badge/License-ISC-lightgrey)

## Features

- **Automatic portal detection:** Detects the Fortinet captive portal and extracts the session-specific authentication token.
- **Automatic login:** Submits your Jamia Wi-Fi credentials using the portal's expected form fields.
- **Automatic reconnection:** Retries authentication when the connection drops or the portal becomes available again.
- **Background execution:** Runs silently without interrupting your work.
- **Scheduled startup:** Can run at Windows sign-in and whenever a network connection is established.
- **No extra dependencies:** Uses built-in PowerShell and Windows tools.

## Getting Started

### Prerequisites

- Windows 10 or Windows 11
- Windows PowerShell 5.1 or PowerShell 7
- Access to the Jamia Wi-Fi network and a valid account
- Administrator privileges for scheduled-task installation

### 1. Configure your credentials

Open `wifi-login.ps1` in a text editor and update the credentials under the `SETTINGS` section:

```powershell
$StudentId = 'YOUR_STUDENT_ID'  # ft_un
$Password  = 'YOUR_PASSWORD'    # ft_pd
```

Replace the placeholders with your own Jamia Wi-Fi login details.

**Security note:** Never commit your actual credentials to a public GitHub repository.

### 2. Enable automatic login

Open PowerShell in the directory containing the script and run:

```powershell
.\wifi-login.ps1 -Install
```

Run PowerShell as **Administrator** if required. The installer registers a Windows Scheduled Task named `WiFi Auto-Login`.

After installation, the script is configured to run at sign-in and when the relevant network connection event occurs. It attempts to authenticate in the background whenever necessary.

### 3. Run it manually

To authenticate without installing the scheduled task, run:

```powershell
.\wifi-login.ps1
```

The script checks the connection, attempts to log in when required, and exits after connectivity has been verified and the grace period has elapsed.

### 4. Uninstall

To remove the scheduled task, run:

```powershell
.\wifi-login.ps1 -Uninstall
```

Run PowerShell as Administrator if Windows requires elevated permissions to remove the task.

## How It Works

The script follows the same general steps you would perform when logging in through a browser.

| Step | Description |
|---|---|
| 1. Detect | Sends an HTTP request to a probe URL to check whether the network redirects to the captive portal. |
| 2. Extract | Reads the redirect or response to identify the portal address and session-specific `magic` token. |
| 3. Initialize | Requests the login page to obtain the necessary cookies and form information. |
| 4. Authenticate | Submits the student ID, password, token, and redirect parameters to the portal. |
| 5. Verify | Checks connectivity and retries when authentication has not succeeded. |
| 6. Exit | Stops after the connection is stable for the configured grace period or the timeout limit is reached. |

The current implementation is configured around a Fortinet-style captive portal. The exact endpoints and authentication fields may need adjustment if Jamia changes its Wi-Fi configuration.

## Configuration

The main settings are grouped near the beginning of `wifi-login.ps1`.

| Setting | Default | Description |
|---|---|---|
| `$PortalBase` | `http://10.2.0.10:8090` | Fallback address of the captive portal. |
| `$ProbeUrl` | `http://neverssl.com/` | HTTP endpoint used to detect portal redirection. |
| `$Redir` | `http://www.msftconnecttest.com/redirect` | Redirect value submitted during authentication. |
| `$CheckEvery` | `5` | Interval between connection checks, in seconds. |
| `$GraceSeconds` | `5` | Time to wait after connectivity is restored before exiting. |
| `$GiveUpMin` | `5` | Maximum number of minutes to attempt login before giving up. |

These defaults reflect the current script configuration. If the campus portal changes its address or authentication flow, update the relevant values accordingly.

## Scheduled Task

The `-Install` option registers a scheduled task named `WiFi Auto-Login` with two triggers:

- **At logon:** Starts the script when you sign in to Windows.
- **Network connection event:** Uses the relevant network-profile event, identified by Event ID `10000`, to trigger the script when a network connection is established.

The task is configured to launch PowerShell in a hidden window, without loading the usual PowerShell profile.

This allows the login process to run in the background without opening a visible terminal window.

## Project Files

| File | Purpose |
|---|---|
| `wifi-login.ps1` | Main script for portal detection, authentication, and connection checks. |
| `wifi-login.log` | Runtime log used for troubleshooting, created next to the script. |

## Security and Privacy

Your Wi-Fi credentials should be treated as sensitive information.

- **Credentials:** The script sends your login details to the configured captive portal. Verify that the portal address is legitimate before using it.
- **Local storage:** Credentials entered directly into the script remain in the local script file unless another component copies or transmits them.
- **Session token:** The `magic` token is retrieved for the current authentication attempt rather than intentionally saved as a permanent credential.
- **Public repositories:** Remove all personal credentials before pushing the project to GitHub or sharing it with others.
- **Network security:** The example portal uses HTTP. Credentials sent over an unencrypted connection may be exposed to other parties with suitable access to the network. Use only the authentication endpoint provided by Jamia's authorized network administrators.

For a more secure implementation, credentials could be retrieved from Windows Credential Manager instead of being stored in plain text.

## Troubleshooting

| Problem | What to check |
|---|---|
| `POST failed: The operation has timed out.` | The portal may be unreachable or the network may still be connecting. The script should retry according to its configured logic. |
| `Access denied during installation` | Open PowerShell as Administrator and retry. |
| `Script execution is blocked` | Check the PowerShell execution policy and use a temporary process-level policy if appropriate. |
| `Automatic login does not start` | Verify that the scheduled task exists, is enabled, and has the expected triggers. |
| `The script runs but login fails` | Check your credentials, portal URL, session token extraction, and form field names. |
| `Internet access remains unavailable` | Confirm that Jamia's Wi-Fi is reachable and that the portal has not changed its authentication process. |

If PowerShell blocks the script, you can allow script execution for the current PowerShell session with:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Only run scripts you have reviewed and trust.

## License

This project is licensed under the **ISC License**. See the `LICENSE` file for details.

## Disclaimer

This is an independent utility created to automate the Wi-Fi login process for personal convenience. It is not an official Jamia Millia Islamia application and is not affiliated with or endorsed by the university.

Use it only with an authorized campus Wi-Fi account and in accordance with the university's network policies.