# Holodeck Control for Noctalia

<p align="center">
  <img src="assets/holodeck-control.png" width="160" alt="Holodeck Control holographic chamber">
</p>

Thin Luau frontend for the repository's deterministic `holodeckctl`
workflow. The plugin targets Noctalia `v5.0.0-beta.7` and declares plugin API
10, which provides the keyboard focus required by the per-profile AWS alias
and region editor as well as closure callbacks in declarative UI trees.

The panel reads backend status, selects one of the two supported deployment
targets (`home-manager` or `existing-nixos`) and the dark/light appearance mode,
saves those choices to the IR, previews the backend plan, and asks for explicit
confirmation before opening `apply` in a terminal. It also presents GitHub,
GitLab, AWS and Windows VM cards backed by their existing commands.
The GitLab action accepts an instance or group URL, extracts the authentication
host, then delegates only web OAuth/SSO to Holodeck. It does not create a
profile, register an SSH key, or change Git routing.
After AWS discovery, the AWS card offers a local editor for every account/role
assignment. The backend automatically creates `us-east-1` and `us-east-2`
profiles for each one. Users can request the deterministic short
recommendation, customize the semantic alias, keep both defaults, retain only
one region, add others, or recommend all aliases at once. The backend generates
a separate profile and suffix for every selected region and preserves those
choices across resynchronization.

The UI follows Noctalia's native panel hierarchy: a compact Control Center-style
navigation rail, an overview, a focused system workflow, and an integration
picker with one provider detail at a time. It uses semantic control sizes,
palette roles supported by the pinned shell, tooltip-labelled icon actions, and
an explicit destructive variant for stopping the Windows VM. The original
holographic-chamber artwork under `assets/` is shared by the launcher, README
and panel header; a reduced companion mark keeps the same identity legible in
the compact navigation rail. The bar uses Noctalia's native `cube-spark` glyph
with the semantic `on_surface` color so it tracks both light and dark themes.

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
holodeckctl action holodeck-setup
holodeckctl action holodeck-doctor
holodeckctl action github-setup
holodeckctl action gitlab-setup
holodeckctl action aws-sync
holodeckctl action windows-up
holodeckctl action windows-status
holodeckctl action windows-rdp
holodeckctl action windows-password-reset
holodeckctl action windows-wipe
holodeckctl action windows-web
holodeckctl action windows-logs
holodeckctl action windows-down
```

The non-JSON `apply` and interactive `action` commands run in a terminal so
output, authentication, choices and any privilege prompt remain visible. The
RDP and Web actions are graphical launchers and run detached from the panel,
without opening a disposable terminal. The Windows view uses Noctalia's native
masked password input and writes a fresh, short-lived request below the private
`XDG_RUNTIME_DIR`; `holodeckctl` opens it without following symlinks, unlinks it
before starting `windowsvm`, and never returns or persists its contents. The
masked field remains only in panel memory for retries and is cleared when the
user leaves the Windows view or closes the panel. Status
only returns provider/profile metadata; it excludes emails, key paths and
secrets.

The explicit **Replace Windows password** action requires a second confirmation
and opens a visible terminal. It stops the VM, creates a recoverable sparse disk
copy, schedules a one-time guest password replacement, recreates only Docker
container metadata, and starts the preserved Windows storage again. It then
uses FreeRDP authentication-only mode to verify the exact textbox credential;
the old-state copy is removed on success and retained for recovery on failure.

**WIPE WindowsVM** is a separate destructive flow. It requires typing `WIPE`,
deletes the complete guest storage, and creates a fresh VM with the current
username/password inputs. The shared directory and Nix-pinned runtime image are
preserved; a failed initial container creation restores the quarantined storage.
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
