# Holodeck Control for Noctalia

<p align="center">
  <img src="assets/holodeck-control.png" width="160" alt="Holodeck Control holographic chamber">
</p>

Thin Luau frontend for the repository's deterministic `holodeckctl`
workflow. The plugin targets Noctalia `v5.0.0-beta.7` and declares plugin API
10, which provides the keyboard focus required by the per-profile AWS alias
and region editor as well as closure callbacks in declarative UI trees.

The native panel opens from the existing `holodeck/control:config` bar widget.
It presents Work and Computer actions at equal priority, with a searchable
catalog and one focused task at a time. There are no overview/system/provider
navigation layers. Common actions take one click; profile selection takes two;
appearance and scope changes take three including confirmation, counted from
the open panel. Data entry and external authentication are additional work.

AWS login reuses the profile shared with the Zsh helpers. Account discovery is
separate from login and alias editing. Alias editing searches account/role
assignments before showing that assignment's fields. Windows opens directly
once configured, while initial credentials, password replacement and VM
recreation have their own task forms. Destructive effects are shown before
confirmation; VM recreation still requires typing `WIPE`.

Appearance and deployment scope remain local drafts until the user confirms.
A fixed `apply-change` command validates and saves the choice under the IR lock
before running the installer. The home view refreshes configuration status;
interactive commands retain a visible terminal for authentication and results.

The HTML under `docs/` is a design reference only. Home Manager packages and
loads `panel.luau` inside Noctalia; no browser is involved in the actual UI.

## Security boundary

The Luau code never writes the IR and never evaluates backend-provided `argv`.
Every process is selected from a static allowlist. During packaging, Nix
replaces `@holodeckctl@` with the immutable store path of the repository's
backend wrapper; the suffixes below remain literals:

```text
holodeckctl --json status
holodeckctl --json init
holodeckctl --json set deployment.target home-manager
holodeckctl --json set deployment.target existing-nixos
holodeckctl --json set appearance.theme.mode dark
holodeckctl --json set appearance.theme.mode light
holodeckctl --json set integrations.windows.rdp.displayMode half
holodeckctl --json set integrations.windows.rdp.displayMode fullscreen
holodeckctl --json plan
holodeckctl --json aws-aliases-apply
holodeckctl apply
holodeckctl apply-change theme-dark
holodeckctl apply-change theme-light
holodeckctl apply-change scope-user
holodeckctl apply-change scope-system
holodeckctl apply-change saved
holodeckctl --json aws-profile-select
holodeckctl action aws-login
holodeckctl action holodeck-setup
holodeckctl action holodeck-doctor
holodeckctl action github-setup
holodeckctl action gitlab-setup
holodeckctl action aws-sync
holodeckctl action windows-up
holodeckctl action windows-status
holodeckctl action windows-rdp
holodeckctl action windows-unlock
holodeckctl action windows-password-reset
holodeckctl action windows-wipe
holodeckctl action windows-web
holodeckctl action windows-logs
holodeckctl action windows-down
```

The non-JSON `apply` and interactive `action` commands run in a terminal so
output, authentication, choices and any privilege prompt remain visible. The
Windows onboarding asks for a username/password only once. After VM creation or
successful RDP authentication, `windowsvm` stores the credential in a
user-owned mode-0600 file inside the VM storage. Status validates that file but
returns only a readiness boolean, username, and RDP-policy version; it never
returns the password. The panel then removes the credential inputs and exposes
one primary **Open Windows** action.

The first managed launch waits through a fresh Dockurr installation, creates a
recoverable sparse copy, schedules an ADSI WinNT unlock and local lockout
threshold `0` as `SYSTEM`, validates RDP, and records that the one-time setup is
complete. Later launches reuse the private credential without showing it. If
Windows still reports a locked account, the same repair runs once automatically
and reopens RDP. A private operation lock rejects duplicate launch/maintenance
clicks, and explicit authentication rejection is never retried.

An explicit field value is handed off through a fresh, short-lived request below
the private `XDG_RUNTIME_DIR`; `holodeckctl` opens it without following symlinks
and unlinks it before starting `windowsvm`. It replaces the private copy only
after successful creation or authentication, so a typo does not overwrite the
working secret. Status excludes emails, key paths and all secrets.

The **Change Windows password** task shows its effects and credential fields
before confirmation and opens a visible terminal. It stops the VM, creates a recoverable sparse disk
copy, schedules a one-time guest password replacement, recreates only Docker
container metadata, and starts the preserved Windows storage again. It then
uses FreeRDP authentication-only mode to verify and privately persist the exact
textbox credential;
the old-state copy is removed on success and retained for recovery on failure.

**WIPE WindowsVM** is a separate destructive flow. It requires typing `WIPE`,
deletes the complete guest storage including the stored credential, and creates
a fresh VM with the current username/password inputs. The shared directory and
Nix-pinned runtime image are preserved; a failed initial container creation
restores the quarantined storage.
Alias text never enters a command string. The panel writes a transient JSON
request in its Noctalia state directory, then invokes the fixed
`aws-aliases-apply` command; the backend validates and removes that request.

The source tree intentionally retains the replacement token, so it can be
linted directly but must be installed through the Nix package before it can run.

## Entry points

- Widget: `holodeck/control:config`
- Panel: `holodeck/control:control`

Open the panel directly with:

```console
noctalia msg panel-toggle holodeck/control:control
```

Validate the manifest/backend-setting contract offline with:

```console
noctalia plugins lint plugins/noctalia/holodeck-control
```
