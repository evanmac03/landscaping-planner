# GitHub push, draft release and publication

## Inside Godot

Enable **GitHub workflow** under **Project > Project Settings > Plugins**.
The GitHub dock is enabled by default in this project. Save your scenes/scripts
before refreshing status; Git reads disk, not unsaved editor buffers.
The dock has five tabs: **Git** for local commits, **Push** for PRs,
**Release** for draft exports/recovery, **Publish** for final publication,
and **Guided workflow** for a question-by-question walkthrough.
The version entered in Release is also displayed and used in Publish.
All tabs share the command output panel.

### Guided workflow

Save all files and review/test the changes, then choose **Guided workflow >
Start**. The guide asks which files to stage, a feature branch name when on
main, the commit name, and approval to push to GitHub. Existing staged files
are included in the commit; later unstaged edits are not. Push still requires
a clean checkout, so handle any excluded dirty work deliberately.
Branch name, commit name and staged-diff review now share one screen. Its
**Create commit** approval creates the requested feature branch when needed
and commits the reviewed index. If branch creation succeeds but commit fails,
the new branch remains; inspect output rather than blindly restarting.
**Back** from commit review refreshes the file screen without undoing staging
and retains the branch and commit names. Back from draft preparation returns
to the manual-merge checkpoint and retains version/editor input. Back from
publication pauses for testing; it never reruns draft preparation or undoes a
draft. Publication approval must always be given again.
The file question has a checkbox beside each path, with **Select all** and
**Select none** buttons. Files start unchecked; check the files you reviewed
before clicking **Stage selected**.
The guide blocks partial file selection before staging: leaving dirty files out
would otherwise allow a commit that cannot be pushed by this workflow. It also
checks for remaining unstaged work before commit and a clean feature branch
before Push. Use the individual Git tab for partial commits instead.

Before asking for a commit name, the guide loads the exact reviewed staged diff
(including added text files) and asks you to confirm review. Binary contents are
not displayed and must be reviewed separately. Invalid branch names, blank
commit messages, malformed versions, missing Godot executables and missing
publication approval produce inline errors without losing your answers.

After Push, the guide pauses: review the PR and any checks, merge on GitHub,
then switch to main and synchronize it outside the dock. Continue the dialog,
or cancel and use **Resume after manual PR merge and sync** later.
The guide does not merge, pull or stash. The release backend freshly fetches
and verifies that main is synchronized before creating a draft.

Next it asks for an unused version, Godot executable, and approval to prepare
the tag/private draft. After successful preparation it asks separately for
publication, including confirmation that you tested the downloaded Windows
package. Publication never runs merely because preparation succeeded.
**Resume at verified draft publication** asks for the exact prepared version
and the same separate approval; the backend still requires the matching local
receipt and exact clean commit.

Cancel stops at the current question without undoing prior operations.
An error stops the guide; inspect output and GitHub before retrying, especially
after a possible partial remote write. Interrupted drafts still use the
Release tab's recovery controls. The guide does not persist its progress across
editor restarts; use the resume buttons and existing receipts deliberately.
It uses GitHub only, with no Forgejo backup, automatic tests or CI certification.
The progress indicator shows the current stage, and buttons open GitHub's PR
and release lists. Command results are retained in the shared output panel for
the current dock session, including automatic status refreshes. Output is not
saved across editor restarts and is available only after each command finishes.
Long questions/reviews scroll within the dialog. A failed or malformed status
response clears the old selection/snapshot and stops the guide until refreshed.

### Individual tabs

1. Refresh status, inspect Tracked diff, then select individual files in Changes
   and click **Stage selected**. This writes their saved contents to Git's real
   index. The separate **Staged changes** list shows the next commit.
   Untracked files are listed but their contents are not shown in Tracked diff;
   open and review them separately, especially for credentials and large assets.
2. On main, enter a `feature/lowercase-kebab-name` branch and create it.
   Status refreshes after staging, unstaging, branch creation and commits.
3. Review staged diff, click **Commit**, then enter the commit name/message and
   confirm **Create commit**. All staged changes are committed, including changes
   staged externally before the last refresh. Changes to the index since that
   refresh block the commit. Later working-file edits are left unstaged.
   **Unstage selected** removes files from the index without losing their edits.
   Staging uses whole files, not individual hunks, and commits do not run tests.
4. Push opens/reuses a PR; review tests and merge separately on GitHub.
5. Prepare Release only after synchronizing clean main outside the dock.
   Enter the version and editor path; confirmation creates a tag and draft.
6. Use RecoverDraft only for an interrupted preparation with a retained build.
   GUI-test the downloaded ZIP before confirming Publish separately.

Commands run in a background thread; output appears when each completes.
Do not disable the plugin or close Godot while a command runs: shutdown waits
for the command and does not cancel remote mutations. The dock never pulls,
merges, discards edits, force-pushes, or stores GitHub tokens. Authentication
uses the existing `gh` CLI login. Run `gh auth login` in a terminal if needed.

Run [tools/github.ps1](../tools/github.ps1) from PowerShell 5.1 or newer.
It targets `evanmac03/landscaping-planner` on GitHub only. It does not use the
separate os_agent repository's scripts or Forgejo backups.

Prerequisites:

- Git and GitHub CLI (`gh`), authenticated with access to the repository.
- For Release: Godot 4.7.x and matching Windows x86_64 export templates.
  Install templates using Godot's **Editor > Manage Export Templates**.
- A clean, committed checkout for Push, Release and Publish. The script never stages, commits, stashes,
  rebases, merges, force-pushes or changes branches.

```powershell
# Local information only; safe with uncommitted work.
.\tools\github.ps1

# After creating a feature branch and committing the intended changes:
.\tools\github.ps1 -Action Push -Approve

# Review the PR and GitHub checks, then merge separately.
# Switch to main and synchronize it yourself before preparing:
.\tools\github.ps1 -Action Release -Version v0.1.0-rc.1 -Approve

# Optional explicit editor location:
.\tools\github.ps1 -Action Release -Version v0.1.0-rc.1 -Godot 'C:\path\Godot_console.exe' -Approve

# Download and manually test the draft ZIP before this separate approval:
.\tools\github.ps1 -Action Publish -Version v0.1.0-rc.1 -Approve
```

## Guarantees and limits

Push fetches origin, rejects remote-only feature commits, pushes the feature
branch and reuses or creates its PR against main. It stops before merge.
It does not run tests or wait for CI; review those separately. Its PR body
explicitly states this limitation.

Release requires clean main at the freshly fetched origin/main commit and an
unused version. It exports a committed-source archive in private Git metadata,
not the working tree. The Windows preset excludes tests, developer tools,
documentation, preview files, Ziva editor tooling and the alternate project
configuration. Data files are included. Builds are unsigned.
After a successful export it pushes a lightweight version tag pointing to that
exact commit, then creates the draft against that existing tag. Preparing a
draft therefore writes a tag to GitHub but does not publish a release.
Draft lookup uses GitHub CLI to resolve the release's database ID, then reads
that exact release through the API and checks its tag and ID. The REST
release-by-tag endpoint does not reliably resolve unpublished drafts.

The ZIP contains the executable, separate PCK and any companion export files.
A SHA-256 checksum is uploaded beside it. The draft's uploaded asset list and
downloaded hashes are verified before a local preparation receipt is saved
under `.git/landscaping-releases` (the actual Git metadata directory is resolved
for worktrees). These files are private local state, not source.

Publish requires that receipt, the same clean main commit, the same draft ID,
an exact matching remote tag, and freshly downloaded matching assets. It
rechecks that the draft did not change during verification. Publication is a
separate explicit `-Approve` operation. A prerelease version containing `-`
is labelled as a GitHub prerelease.

Neither an export nor a matching checksum proves that the game is playable.
Run project tests and manually test the downloaded package before publication.
No runtime smoke test, CI gate, installer or code signing is provided.

## Failures and recovery

Native command failures stop the script. Failed builds are retained under the
Git metadata directory for inspection; templates are never installed
automatically. Build folders can be large.

If a push succeeds but PR creation fails, inspect GitHub and run Push again
only after confirming the branch state. It will reuse an existing PR.

If draft creation/upload or verification fails, inspect GitHub before doing
anything else. Do not blindly rerun Release: existing tags/releases are
rejected, and no preparation receipt is written until verification succeeds.
Keep the retained build, fix or remove the incomplete draft deliberately,
and use a new version if its tag exists. There is no automatic repair of
partially uploaded drafts.

For an intact draft whose preparation stopped before saving its receipt:

```powershell
.\tools\github.ps1 -Action RecoverDraft -Version v0.1.0-rc.1 -BuildDirectory 'C:\project\.git\landscaping-releases\build-EXACT-ID' -Approve
```

Use the exact retained build directory reported by Release. Recovery requires
main synchronized with origin/main, the same committed source archive, original
ZIP/checksum, matching draft target/tag, and freshly downloaded matching assets.
It trusts the retained local build provenance; it does not prove reproducible
compilation. It does not rebuild, upload, publish, or overwrite an existing
receipt. Unlike publication, recovery allows dirty files because it verifies
the committed archive rather than exporting the working tree; this permits
repairing the workflow without losing the original draft. Publish still
requires a clean checkout of the receipt's exact commit.

If Publish reports an error after its mutation, inspect the release on GitHub.
An already-published release is rejected on retry, not recreated.
Loss of the local preparation receipt blocks scripted publication until the
existing draft is recovered and verified as described above.

## Testing the automation

```powershell
.\tools\test-github.ps1
.\tools\test-editor-git.ps1
# With Godot on PATH, check the real dock background Status command:
godot --headless --path . --script tools/check_github_dock.gd
```

This runs isolated workflow checks with simulated native commands, including
draft preparation, publication, dirty-checkout and approval guards, remote
branch divergence, asset tampering and repeat-publication rejection. It does
not contact GitHub, export a real game or publish anything.
