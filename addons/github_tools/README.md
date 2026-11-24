# Godot Dev Workflow

Install this entire `github_tools` folder under your project's `addons` folder.
Enable **Godot Dev Workflow** in Project Settings > Plugins. Godot 4.7 is the
tested editor version; Windows PowerShell 5.1 or PowerShell 7, Git and GitHub CLI
are required. Optional AI advice is off by default and never required.

## Project setup

Copy `dev-workflow.example.json` to your project root as `dev-workflow.json`.
Set `provider` to `GitHub` and `repository` to your exact `owner/repository`.
The origin remote must match that repository (HTTPS or GitHub SSH).
Reload the plugin after changing configuration. Forgejo is not implemented.

Local Git works without hosting configuration. GitHub operations fail explicitly
until configured. GitHub CLI uses your existing authenticated account; never put
tokens in this file. Every mutation requires approval. The addon never merges,
stashes, force-pushes or discards changes. Individual operations use the same
review/approval dialogs as the guide, stopping after the selected operation.

`validation` and `release` are optional until those operations are used:

- `validation.script`: a trusted project-relative `.ps1` entry point accepting
  `-Godot PATH`. It must throw or exit nonzero on failure. The addon executes
  project code only after the user requests validation; review it first.
  Include the addon acceptance checks in your own tests. No default project
  test command or success is invented.
- `release.product`: a lowercase filename slug, e.g. `my-game`.
- `release.preset`: your Windows x86_64 export preset, e.g. `Windows Desktop`.
  Configure matching Godot export templates and a separate, nonembedded PCK.
- `release.godot_version`: the exporter major.minor version, e.g. `4.7`.

Releases currently require clean `main` exactly matching `origin/main`.
Preparation exports committed source in isolation, uploads a private draft,
and verifies assets. Publish downloads/tests that exact package and requires
separate approval. This is a Windows game release, not an addon release.
Configure your export preset to exclude editor addons from the game.

The addon includes its three runtime PowerShell helpers in `tools`; it does not
depend on scripts from the original project's root. Existing private metadata
directory names are retained for compatibility with earlier receipts.
The read-only agent CLI in the original project is optional, not a runtime
dependency of the addon.

## Distribution and acceptance

`tools/package-addon.ps1 -Output C:\outside-project\godot-dev-workflow.zip`
creates an installable archive containing only this addon, including these
instructions and the example configuration. It does not package your project
configuration, code, credentials or private Git receipts. It never publishes.
Choose licensing terms before distributing the addon publicly.

In the source project, `tools/test-addon.ps1 -Godot PATH` packages, installs into
a disposable unrelated project, verifies local Git and setup errors, boots the
actual editor with the plugin enabled and checks that its named dock exists.
This is separate from exported-game startup/playtesting. Automated editor
acceptance does not replace a human usability walkthrough.
