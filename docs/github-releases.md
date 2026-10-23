# GitHub push, draft release and publication

Run [tools/github.ps1](../tools/github.ps1) from PowerShell 5.1 or newer.
It targets `evanmac03/landscaping-planner` on GitHub only. It does not use the
separate os_agent repository's scripts or Forgejo backups.

Prerequisites:

- Git and GitHub CLI (`gh`), authenticated with access to the repository.
- For Release: Godot 4.7.x and matching Windows x86_64 export templates.
  Install templates using Godot's **Editor > Manage Export Templates**.
- A clean, committed checkout. The script never stages, commits, stashes,
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

If Publish reports an error after its mutation, inspect the release on GitHub.
An already-published release is rejected on retry, not recreated.
Loss of the local preparation receipt blocks scripted publication.

## Testing the automation

```powershell
.\tools\test-github.ps1
```

This runs isolated workflow checks with simulated native commands, including
draft preparation, publication, dirty-checkout and approval guards, remote
branch divergence, asset tampering and repeat-publication rejection. It does
not contact GitHub, export a real game or publish anything.
