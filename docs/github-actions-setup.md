# GitHub Actions TestFlight setup

This guide explains how to configure the GitHub Actions secrets used to sign,
archive, and upload Wiggle Room builds to TestFlight. It is intended for
maintainers of this repository and developers configuring their own fork.

The workflows create separate iOS and macOS archives. They use Xcode automatic
signing with an App Store Connect API key, an Apple Distribution certificate,
and a Mac Installer Distribution certificate. Never commit any private key,
certificate export, password, or secret value to the repository.

## Prerequisites

Before configuring the secrets, ensure that:

- You have an active Apple Developer Program membership.
- An app record exists in App Store Connect for both supported platforms.
- Your Apple Developer account has identifiers and capabilities for the main
  app and its embedded watch and widget targets.
- Your fork uses bundle identifiers, App Groups, and CloudKit containers owned
  by your Apple Developer team.
- You can access the repository's **Settings → Secrets and variables →
  Actions** page.

The repository workflows expect all eight secrets listed below. GitHub does not
allow empty Actions secrets, and it does not display a secret again after it is
saved.

## Required secrets

| Secret | Purpose |
|---|---|
| `APPLE_TEAM_ID` | Selects the Apple Developer team used for code signing and provisioning. |
| `APP_STORE_CONNECT_API_KEY_ID` | Identifies the App Store Connect API private key. |
| `APP_STORE_CONNECT_ISSUER_ID` | Identifies the App Store Connect API key issuer. |
| `APP_STORE_CONNECT_API_PRIVATE_KEY` | Authenticates Xcode to App Store Connect and Apple's provisioning services. |
| `APPLE_DISTRIBUTION_CERTIFICATE_BASE64` | Supplies the Apple Distribution signing identity used to sign the apps and extensions. |
| `APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD` | Unlocks the exported Apple Distribution `.p12`. |
| `MAC_INSTALLER_DISTRIBUTION_CERTIFICATE_BASE64` | Supplies the installer signing identity required for Mac App Store distribution. |
| `MAC_INSTALLER_DISTRIBUTION_CERTIFICATE_PASSWORD` | Unlocks the exported Mac Installer Distribution `.p12`. |

## Add a repository secret

Repeat these steps for each secret:

1. Open the GitHub repository.
2. Select **Settings**.
3. Select **Secrets and variables → Actions**.
4. Select **New repository secret**.
5. Enter the exact secret name shown in this guide.
6. Enter its value and select **Add secret**.

Use repository secrets rather than repository variables. Do not put actual
values in workflow files, documentation, issues, pull requests, or logs.

## `APPLE_TEAM_ID`

### What it is for

The Team ID uniquely identifies the Apple Developer team that owns the signing
certificates, bundle identifiers, capabilities, and provisioning profiles.
Both workflows pass it to Xcode as `DEVELOPMENT_TEAM` and include it in the
archive export configuration.

### How to obtain it

1. Sign in to the [Apple Developer account](https://developer.apple.com/account).
2. Open **Membership details**.
3. Find the **Team ID** associated with the team that owns the app.
4. Copy the Team ID exactly.
5. Add it to GitHub as `APPLE_TEAM_ID`.

Do not use the App Store Connect provider ID, an individual Apple ID, or the
team name. If your account belongs to multiple teams, select the team that owns
the app identifiers and App Store Connect app record.

## App Store Connect API secrets

The three App Store Connect API secrets belong to one team API key. The
workflows use the key to let Xcode manage provisioning and upload archives
without storing an Apple ID password or app-specific password.

### Create the API key

1. Sign in to [App Store Connect](https://appstoreconnect.apple.com/).
2. Open **Users and Access**.
3. Open **Integrations → App Store Connect API**.
4. Create a new **Team Key**.
5. Give it a descriptive name for this GitHub Actions deployment.
6. Select the **App Manager** role.
7. Enable access to **Certificates, Identifiers & Profiles**.
8. Create the key.
9. Download its `.p8` private key immediately.

Apple permits the `.p8` file to be downloaded only once. Store the original in
an approved secure location. If it is lost, revoke the key and create a new
one; it cannot be downloaded again.

### `APP_STORE_CONNECT_API_KEY_ID`

#### What it is for

The Key ID tells App Store Connect which public API key corresponds to the
private `.p8` key installed by the workflow.

#### How to obtain it

1. Return to **Users and Access → Integrations → App Store Connect API**.
2. Find the team key created for GitHub Actions.
3. Copy its **Key ID** exactly.
4. Add it to GitHub as `APP_STORE_CONNECT_API_KEY_ID`.

The Key ID is not the key name and is not the Issuer ID.

### `APP_STORE_CONNECT_ISSUER_ID`

#### What it is for

The Issuer ID identifies the App Store Connect organization that issued the API
key. Xcode requires it alongside the Key ID and private key.

#### How to obtain it

1. Open **Users and Access → Integrations → App Store Connect API**.
2. Locate the **Issuer ID** shown on the API page.
3. Copy it exactly, including its hyphens.
4. Add it to GitHub as `APP_STORE_CONNECT_ISSUER_ID`.

### `APP_STORE_CONNECT_API_PRIVATE_KEY`

#### What it is for

This is the private half of the App Store Connect API key. During a workflow,
it is written to a temporary `AuthKey_<key-id>.p8` file with restricted
permissions. Xcode uses it to authenticate provisioning and upload operations,
and the workflow removes it during cleanup.

#### How to obtain and store it

1. Locate the `AuthKey_<key-id>.p8` file downloaded when the API key was
   created.
2. Open it in a plain-text editor.
3. Copy its complete contents, including:

   ```text
   -----BEGIN PRIVATE KEY-----
   ...
   -----END PRIVATE KEY-----
   ```

4. Add the complete text to GitHub as
   `APP_STORE_CONNECT_API_PRIVATE_KEY`.

Do not Base64-encode this value. Do not remove its header, footer, or line
breaks. Never commit or share the `.p8` file.

## Apple Distribution certificate secrets

The Apple Distribution certificate signs the app and embedded extensions for
App Store distribution. The workflow needs a `.p12` containing both the
certificate and its matching private key. A downloaded `.cer` file alone is
not sufficient.

### Create and install the certificate

The simplest approach is to let Xcode create the certificate:

1. On a trusted Mac, open **Xcode → Settings → Accounts**.
2. Select the Apple ID and team that own the app.
3. Select **Manage Certificates…**.
4. Select **+ → Apple Distribution**.
5. Close the certificate manager.
6. Open **Keychain Access**.
7. Select the **login** keychain and **My Certificates**.
8. Find **Apple Distribution: …**.
9. Expand it and confirm that a private key appears underneath.

If Xcode cannot create the certificate, create a certificate signing request
with **Keychain Access → Certificate Assistant → Request a Certificate From a
Certificate Authority**, choose **Saved to disk**, and upload it when creating
an **Apple Distribution** certificate in
[Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/certificates/list).
Download and open the resulting `.cer` file on the same Mac that generated the
request.

If no private key appears under the installed certificate, its certificate
signing request was created on another Mac. Obtain a secure `.p12` export from
the person or system that holds the private key, or create a new certificate
using a request generated on your Mac.

### Export the `.p12`

1. In **Keychain Access → login → My Certificates**, expand the
   **Apple Distribution: …** entry.
2. Confirm its private key is visible beneath it.
3. Select the certificate, then Command-click its private key so both items are
   highlighted.
4. Select **File → Export 2 Items…**. If Keychain Access does not offer the
   Personal Information Exchange (`.p12`) format, stop: the matching private
   key is not selected or is not available on this Mac.
5. Save the export with a descriptive temporary filename and the `.p12`
   extension.
6. At the export-password prompt, choose a non-empty, strong password and enter
   it identically in both fields. This is the value required by
   `APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD`.
7. Keychain Access may then separately request the Mac login password or
   Touch ID to authorize access to the private key. That authorization is not
   the `.p12` export password and must not be saved in GitHub.
8. Store the `.p12` export password securely until it has been added to GitHub.

Before encoding the file, use the
[local import preflight](#test-each-p12-locally-before-uploading-it) below.

### `APPLE_DISTRIBUTION_CERTIFICATE_BASE64`

#### What it is for

GitHub secrets contain text, so the binary `.p12` export is converted to a
single-line Base64 value. The workflow decodes it into a temporary file and
imports the certificate and private key into a temporary keychain.

#### Create the value

In Terminal, replace the filename with the actual path to the export:

```sh
base64 -i AppleDistribution.p12 | tr -d '\n' | pbcopy
```

This copies the encoded value to the clipboard. Add the clipboard contents to
GitHub as `APPLE_DISTRIBUTION_CERTIFICATE_BASE64`.

Do not paste the original binary `.p12`, the `.cer`, or command output that
contains extra prompts. The secret should be one uninterrupted Base64 string.

### `APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD`

#### What it is for

This password unlocks the `.p12` while the workflow imports its signing
identity into the temporary keychain.

Add the exact password chosen during export to GitHub as
`APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD`. This is the `.p12` export password,
not the later Mac login/Touch ID authorization, Apple ID password, or API key.
Do not use a blank export password.

## Mac Installer Distribution certificate secrets

The Mac Installer Distribution certificate signs the installer package
produced for Mac App Store and macOS TestFlight distribution. It is distinct
from Apple Distribution, Mac App Distribution, and Developer ID Installer.
The workflow needs a `.p12` containing both this certificate and its private
key.

### Create a certificate signing request

1. On a trusted Mac, open **Keychain Access**.
2. Select **Keychain Access → Certificate Assistant → Request a Certificate
   From a Certificate Authority**.
3. Enter the email address associated with the Apple Developer account.
4. Enter a descriptive common name.
5. Select **Saved to disk**.
6. Save the `.certSigningRequest` file securely.

### Create and install the certificate

1. Open
   [Apple Developer Certificates](https://developer.apple.com/account/resources/certificates/list).
2. Select **+** to create a certificate.
3. Under **Software**, select **Mac Installer Distribution**.
4. Continue and upload the `.certSigningRequest` file.
5. Download the resulting `.cer` file.
6. Double-click the `.cer` file to install it in Keychain Access.
7. Open **Keychain Access → login → My Certificates**.
8. Find **Mac Installer Distribution: …**.
9. Expand it and confirm that a private key appears underneath.

Do not choose **Developer ID Installer**; that certificate is for distribution
outside the Mac App Store. Do not use **Mac App Distribution** in place of the
installer certificate.

If no private key appears, the certificate signing request was generated on a
different Mac. Recreate the certificate using a request generated on the Mac
that will export it, or securely obtain a `.p12` from the private-key holder.

### Export the `.p12`

1. In **Keychain Access → login → My Certificates**, expand the
   **Mac Installer Distribution: …** entry.
2. Confirm its private key is visible beneath it.
3. Select the certificate, then Command-click its private key so both items are
   highlighted.
4. Select **File → Export 2 Items…**. If `.p12` is unavailable, stop and
   confirm that the matching private key is selected and stored on this Mac.
5. Save the export with a descriptive temporary filename and the `.p12`
   extension.
6. At the export-password prompt, choose a non-empty, strong password and enter
   it identically in both fields. This is the value required by
   `MAC_INSTALLER_DISTRIBUTION_CERTIFICATE_PASSWORD`.
7. If Keychain Access subsequently requests the Mac login password or Touch ID,
   that is only authorization to export the private key. It is not the `.p12`
   password and must not be saved in GitHub.

Before encoding the file, use the
[local import preflight](#test-each-p12-locally-before-uploading-it) below.

### `MAC_INSTALLER_DISTRIBUTION_CERTIFICATE_BASE64`

#### What it is for

This secret transports the binary installer certificate and private key to the
macOS workflow as text. The workflow decodes and imports it only for the
duration of the job.

Create the value in Terminal:

```sh
base64 -i MacInstallerDistribution.p12 | tr -d '\n' | pbcopy
```

Add the clipboard contents to GitHub as
`MAC_INSTALLER_DISTRIBUTION_CERTIFICATE_BASE64`.

### `MAC_INSTALLER_DISTRIBUTION_CERTIFICATE_PASSWORD`

#### What it is for

This password unlocks the Mac Installer Distribution `.p12` during import.

Add the exact export password to GitHub as
`MAC_INSTALLER_DISTRIBUTION_CERTIFICATE_PASSWORD`. It is independent of the
Apple Distribution certificate password and may be different. Do not use the
Mac login password or a blank export password.

## Test each `.p12` locally before uploading it

Test the exact exported file and password before creating its Base64 secret.
This preflight mirrors the workflow's `security import` operation, uses a
temporary keychain, and does not place the password in shell history.

In Terminal, set `P12_PATH` to the exported file and run:

```zsh
(
  set -e
  P12_PATH="$HOME/path/to/Certificate.p12"
  TEMP_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp/}wiggleroom-signing.XXXXXX")"
  TEMP_KEYCHAIN="$TEMP_DIRECTORY/test.keychain-db"
  TEMP_KEYCHAIN_PASSWORD="$(openssl rand -hex 32)"
  trap 'security delete-keychain "$TEMP_KEYCHAIN" 2>/dev/null || true; rm -rf "$TEMP_DIRECTORY"' EXIT

  read -s "P12_PASSWORD?Enter the .p12 export password: "
  echo
  security create-keychain -p "$TEMP_KEYCHAIN_PASSWORD" "$TEMP_KEYCHAIN"
  security unlock-keychain -p "$TEMP_KEYCHAIN_PASSWORD" "$TEMP_KEYCHAIN"
  security import "$P12_PATH" \
    -P "$P12_PASSWORD" \
    -T /usr/bin/security \
    -f pkcs12 \
    -k "$TEMP_KEYCHAIN"
)
```

A valid file/password pair reports that identities or items were imported. If
it reports `The user name or passphrase you entered is not correct`, do not
encode or upload that file. Re-export it and carefully distinguish:

1. the new `.p12` export password, which belongs in the GitHub password secret;
2. the Mac login password or Touch ID prompt that merely authorizes Keychain
   Access to export the private key.

Run the preflight separately for the Apple Distribution `.p12` and Mac
Installer Distribution `.p12`. After each successful test, encode that exact
file and pair it with that exact export password in GitHub. The parentheses run
the commands in a subshell, so the password leaves the environment and the
temporary keychain is deleted as soon as the test finishes.

## Certificate import failures

Both workflows import `APPLE_DISTRIBUTION_CERTIFICATE_BASE64` first. Therefore,
if iOS and macOS both fail at their certificate step with
`SecKeychainItemImport: The user name or passphrase you entered is not
correct`, replace and retest this shared pair first:

- `APPLE_DISTRIBUTION_CERTIFICATE_BASE64`
- `APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD`

That failure does not yet test the Mac Installer Distribution secrets. The
macOS workflow imports those only after the Apple Distribution identity
succeeds.

The workflow passes secret values through environment variables and decodes
the Base64 data into a temporary file. Password punctuation does not require
shell escaping. The error means that the decoded file and password are not a
valid matching PKCS#12 pair—for example, the wrong password was saved, the Mac
login password was confused with the export password, or the wrong file was
encoded.

## Verify the configuration

After all eight secrets are present:

1. Confirm every secret name exactly matches this guide.
2. Confirm both Base64 secrets were created from `.p12` files that include
   their private keys.
3. Confirm each password matches its corresponding `.p12`.
4. Confirm the API Key ID, Issuer ID, and `.p8` all belong to the same team API
   key.
5. Confirm `APPLE_TEAM_ID` identifies the team that owns the app and
   capabilities.
6. Run the iOS and macOS workflows manually or push to a configured deployment
   branch.
7. Inspect failures only through GitHub Actions logs; never print secret values
   while troubleshooting.
8. After successful uploads, confirm both builds appear in App Store Connect
   under TestFlight.

Workflow runs perform real TestFlight uploads. Each attempt receives a unique,
platform-specific build number, including reruns.

## Secret rotation and cleanup

- Revoke and replace an App Store Connect API key immediately if its `.p8`
  private key may have been exposed.
- Replace the Key ID, Issuer ID, and private-key secrets together when rotating
  the API key.
- Replace both the Base64 and password secrets when rotating a `.p12`.
- Re-export certificate secrets before their Apple certificates expire.
- Delete temporary local `.p12`, `.cer`, CSR, and clipboard contents when they
  are no longer needed, while retaining approved secure backups where required.
- Never expose values in screenshots, support requests, issues, or workflow
  debugging output.
