# GitHub push, draft release and publication

## Inside Godot

Enable **GitHub workflow** under **Project > Project Settings > Plugins**.
The GitHub dock is enabled by default in this project. Save your scenes/scripts
before refreshing status; Git reads disk, not unsaved editor buffers.
The dock has six tabs: **Git** for local commits, **Push** for PRs,
**Release** for draft exports/recovery, **Publish** for final publication,
**Guided workflow** for a question-by-question walkthrough, and **AI adviser**
for optional advice.
The version entered in Release is also displayed and used in Publish.
All tabs share command output, current step/result messages and validation/CI evidence.

The individual **Git**, **Push**, **Release** and **Publish** operations use the
same question dialogs, status refresh, reviewed snapshots, command construction
and approvals as Guided workflow. Only their scope differs:

- **Git → Review and commit** reviews files and the staged diff, asks for the
  branch/name and explicit diff approval, then offers committed-head validation.
  It stops before Push. As in the guide, resolve excluded dirty work first.
- **Push** reviews the clean feature HEAD and opens/reuses its PR, then stops.
  It does not merge or begin Release.
- **Release** asks for the version/exporter and prepares a private draft, then
  stops before package testing or publication.
- **Publish** requires download verification, interactive-test confirmation,
  a fresh local package-integrity check and separate final approval of the exact
  draft identity. It never skips testing simply because it was opened directly.

Result dialogs say **Done** for individual operations; Guided workflow offers
the next step. Cancel leaves completed work in place. Git's status/diff,
stage/unstage and branch tools, Push's fetch/readiness tools and interrupted
draft recovery remain explicit supporting utilities, not alternate commit or
publication approval paths. The optional AI adviser is not required.

### Optional AI adviser

AI assistance starts **Off** every time the dock is created. It is never
required for staging, checks, PRs, synchronization, drafts, testing or publishing.
Turning it on enables only the manual adviser panel; no provider, account,
credentials, automatic connection or network traffic is configured.
Turning it off clears pending requests, pasted responses and displayed advice.
It does not cancel normal workflow operations or erase already-copied clipboard
contents. Adviser data is not saved across editor restarts.

Choose **Explain this step**, **Review this run** or **Suggest workflow
improvements** to generate a request preview. The context includes only
capture time, preview/live mode, an allowlisted step, running/status-available
flags, staged/unstaged counts and package-selected status. These are
point-in-time observations, not fresh readiness checks. No source code, paths,
filenames, branch names, hashes, logs, URLs or free-form project text are sent.
The request also includes the last 20 session operation outcomes (allowlisted
operation, completed/failed-or-unconfirmed, mode and UTC capture time), plus
sanitized validation/CI states and check status/conclusion enums. No check
names, logs, URLs, raw errors or publication receipt contents are included.
Completed means the command returned successfully, not independent proof of
CI, playability or publication. Preview observations are labelled separately
and real-session observations are restored on exit. These summaries can become
stale; ask for suggestions, not certification of a release.

Review the JSON, check the copying consent box, then **Copy reviewed request**.
Paste it into your chosen Ziva, MCP-connected agent, local model or other
assistant. Sharing is manual and subject to that assistant's privacy policy.
Paste its response JSON into the panel and choose **Display advice only**.
Advice is untrusted plain text: no commands, clickable actions, workflow
transitions or approvals are executed, even if the response asks for them.
Malformed, oversized, unknown-field or wrong-request responses fail explicitly
and clear previously displayed advice. Errors never block the ordinary guide.

#### Provider-neutral adapter contract (v1)

The previewed request has `schema: "guided-workflow-adviser/v1"`, an opaque
`request_id`, `intent` (`explain_step`, `review_run`, `suggest_improvements`),
`context`, read-only `instructions`, and an example `response_format`.
The response must contain exactly:

```json
{
  "schema": "guided-workflow-adviser/v1",
  "request_id": "copy-the-current-request-id",
  "suggestions": ["A plain-text suggestion, not an executable action."]
}
```

Responses are limited to 32768 characters and 1-10 nonempty suggestions of at
most 2000 characters each. The ID must match the current request. A new request
invalidates the previous response and resets sharing consent.
The isolated [adviser panel](../addons/github_tools/adviser_panel.gd) owns
request generation and response validation; its context source is the dock's
allowlisted summary. It has no workflow execution callback.
Future adapters can translate this contract to MCP, agent or model protocols,
but there is no universal live transport implemented here. MCP servers and
LLM APIs are not interchangeable protocols. Each live adapter will require
explicit setup, consent, privacy handling and independent tests; it must not
gain workflow execution or approval authority.

### Guided workflow

#### Read-only agent interface

[workflow-agent.ps1](../tools/workflow-agent.ps1) exposes a versioned,
provider-neutral CLI for Ziva or another agent that can invoke PowerShell.
It is not an MCP server and does not install tools into Ziva. If the agent
cannot launch PowerShell, run it yourself and share the reviewed JSON.
It reuses the same status/evidence/discovery backends as the dock, not live
editor controls or unsaved editor buffers. AI is not required.

```powershell
.\tools\workflow-agent.ps1
.\tools\workflow-agent.ps1 -Action Status
.\tools\workflow-agent.ps1 -Action Evidence
.\tools\workflow-agent.ps1 -Action NextStep
# Only with permission to read GitHub and refresh/prune local tracking refs:
.\tools\workflow-agent.ps1 -Action Evidence -Remote
.\tools\workflow-agent.ps1 -Action NextStep -Remote
```

Supported actions are exactly `Capabilities` (default), `Status`, `Evidence`
and `NextStep`. Local calls never authenticate or contact GitHub. Status
includes disk file names/hashes, branch, HEAD, staged paths and index tree;
the existing helper may write Git tree objects but does not stage or change
files/index contents. Evidence reads existing validation only; it never runs
checks, launches a build or writes a validation receipt.
`NextStep` without `-Remote` reads disk status and returns an advisory enum:
`review_dirty_work`, `review_staged_changes`, `choose_branch` (detached),
`inspect_main_readiness` or `inspect_feature_remote_state`, with explanatory
guidance and captured commit. Dirty work takes precedence over staged-only
work. It never infers remote readiness or approves execution.

`-Remote` is accepted only for Evidence/NextStep. Those reuse the dock's
GitHub queries and fetch/prune origin tracking refs; this is inspection with
local metadata effects, not a strictly zero-write operation. They never push,
merge, synchronize main, prepare drafts or publish. Existing `gh` login and
expected repository origin are required. Remote CI retrieval failure may return
`ok: true` with `data.ci.state: "unavailable"`: the inspection succeeded but
the evidence is unavailable, **not passed**. Discovery failures return an error.
Discovery checks open feature PRs, then exact-head merged PRs if none is open.
A merged match routes to synchronization approval rather than Push; a
different-head open PR or ambiguous match stops for reconciliation.
When no open PR exists, Evidence queries up to 100 workflow runs for the exact
commit, keeping the newest run for each workflow name. It exposes raw run
status/conclusion separately and never converts absent runs into a pass.
All next-step results are advisory only.

Stdout contains one JSON envelope with `schema: "guided-workflow-agent/v1"`,
`action`, `captured_at_utc`, `ok`, `remote_requested`,
`authorization: "none; information only"`, `data` and `error`.
Successful calls exit 0. Rejected actions/backend failures exit 1 with
`ok: false`, `data: null` and
`error: {"code":"inspection_failed","message":"..."}`.
PowerShell argument-binding/startup errors can occur before the envelope
exists; callers must check both exit status and JSON validity.
Backend diagnostics/warnings may appear on other streams; do not treat them
as response JSON. The captured time is request-start time, not a guarantee
that the repository stayed unchanged afterward.

Do not forward raw agent-interface output automatically to a cloud model:
status and error messages may contain private filenames/paths. Review/redact
before sharing, or use the AI adviser panel's limited allowlisted summary.
This interface has no arbitrary command, script, approval or execution
parameter. Mutating action names are rejected. An external agent may have
other tools with write access; these restrictions apply to this interface,
not to every tool the agent possesses.

Example request to Ziva:

> Read the workflow documentation and use workflow-agent.ps1 for read-only
> capabilities, status and local evidence. Explain the result without changing
> anything. Ask before using -Remote. Do not invoke mutating backend actions,
> execute advice, or treat next-step guidance as user approval.

#### Safe preview and visual checks

Use **Preview full guide (no Git/GitHub writes)** to rehearse the real dialogs
with synthetic files, a simulated branch/commit, validation, PR, draft,
download, testing and publication. Every dialog/result is marked **PREVIEW
ONLY**. The command boundary intercepts all actions in preview: no Git,
PowerShell, GitHub calls, downloads or Windows game launch take place.
Preview results are never saved as publication receipts. **Exit preview**
restores your real settings/evidence/package selection and clears synthetic
Git status; refresh real status before continuing. Cancel pauses the preview
but does not switch back to live operations. Use Exit preview explicitly.

Preview is a UI rehearsal, not proof of authentication, CI, export readiness
or game playability. The automated guide test exercises all preview dialog
transitions; a rendered run also checks window layout. A manual walkthrough
in your editor is still useful for focus, keyboard navigation and editor
theme/DPI differences.

**Start / detect next step** reads GitHub state without publishing: dirty work
starts at file selection; a clean feature branch with an exact-head open PR
resumes at manual review/merge; synchronized clean main resumes draft
preparation. If exactly one draft has a matching local receipt and commit,
it resumes testing/publication instead. Multiple matching drafts open a version
chooser rather than starting another release. Unsynchronized clean main opens
a synchronization checkpoint showing local-only/remote-only commit counts;
inspect and synchronize outside the dock, then detect again.
Discovery fetches origin and requires GitHub login.

Success screens use the actual PR/draft URL returned by GitHub, including
temporary draft URLs. The testing screen offers **Download and verify Windows
ZIP**, **Open verified package folder**, and **Launch verified Windows build**.
Downloads are retained in private release metadata, verified against the local
preparation receipt, and extracted without rebuilding or uploading. Launching
requires a separate click and does not certify a successful playtest.
**Run verified build headless startup check** rehashes the package, starts only
that executable without unsupported path overrides, waits for its exit and
checks a dedicated startup log for errors. It rehashes again afterward. Missing
logs, nonzero exit, logged errors or changed files fail explicitly. A 30-second
limit applies only to this local smoke-test process (which is stopped on expiry),
not to release/network writes. A passing smoke test never checks the interactive
testing box or authorizes publication.
Before launching, every extracted file is rehashed against the verified
download manifest, including companion files; changed, missing or added files
block launch, clear the package selection and testing approval, and require a
new download. The same integrity check runs again when accepting interactive
testing confirmation, before the publication approval screen opens.
Both checks run in the background so hashing does not block the editor.
Changing the version clears both the
package selection and the interactive-test checkbox.

Testing and publication are separate screens. Download the exact version,
test it interactively, and confirm testing before clicking **Review
publication**. The final screen shows version, source commit, draft ID and
prerelease/stable status. **Publish this release** is the separate approval.
Back returns to testing with its confirmation cleared.
Guided Push/Release approvals are bound to the displayed branch and commit;
guided Publish is bound to the tested commit, draft ID, version, target,
prerelease flag and receipt asset hashes. Changed identities stop with an
explicit error. Remote assets are still freshly verified before publication.

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
the testing screen pauses without changing the draft; Back from publication
returns to testing. Neither reruns draft preparation or undoes a draft.
Publication approval must always be given again.
The file question has a checkbox beside each path, with **Select all** and
**Select none** buttons. Files start unchecked; check the files you reviewed
before clicking **Stage selected**.
Checkboxes list only files needing staging. A separate **Already staged** list
shows files already included in the next commit; they are never submitted to
Stage again unless they have newer working-file edits. Such files are marked
**staged + newer edits**, and their latest contents require explicit selection.
The guide blocks partial file selection before staging: leaving dirty files out
would otherwise allow a commit that cannot be pushed by this workflow. It also
checks for remaining unstaged work before commit and a clean feature branch
before Push. The individual Git step uses these same scope rules; handle partial
commits outside this workflow.

**Run local workflow checks** runs the mocked GitHub, disposable Git,
squash-merge synchronization, package smoke and Godot guide suites.
It saves a private validation receipt tied to the exact local
branch/HEAD/index and working-file fingerprints, with a UTC timestamp. It is
not a full game test or a CI run. Changing that snapshot makes the receipt
stale. A new validation attempt invalidates the old receipt before running.
**Refresh local / GitHub CI evidence** reads that receipt and the open PR's
check rollup, or exact-commit workflow runs when there is no open PR (including
on main after synchronization). Local results and GitHub CI are displayed separately, including
no open PR, no checks reported, and PR head different from local HEAD. Individual
CI check states/conclusions are shown without treating absent checks/runs as a pass.
Evidence is point-in-time: refresh after changes made outside the dock.
Push and merge prompts show the summary; the merge checkpoint can refresh it
without pushing again. Local workflow mutations mark displayed evidence as
needing refresh. A remote evidence failure preserves the independently checked
local result and reports GitHub CI as **unavailable**, with its error. A local
validation failure does not retain a local success claim.

After a guided commit, the guide offers **Validate this commit** with the Godot
executable field before Push. Cancel pauses; it does not push. A successful
validation refreshes status and opens Push approval; failed or stale validation
stops. Existing committed branches discovered at Start can still use the
separate validation control.

Before asking for a commit name, the guide loads the exact reviewed staged diff
(including added text files) and asks you to confirm review. Binary contents are
not displayed and must be reviewed separately. Invalid branch names, blank
commit messages, malformed versions, missing Godot executables and missing
publication approval produce inline errors without losing your answers.

After Push, the guide pauses: review the PR and any checks, merge on GitHub,
then choose **Synchronize main after GitHub merge...** or switch/synchronize
outside the dock. The synchronization question refreshes local status and binds
approval to the displayed feature branch and HEAD. It verifies an exact-head
merged GitHub PR whose merge commit is included in freshly fetched origin/main,
rejects dirty work or local-only main commits, switches to main and fast-forwards
only. It never merges a PR, rebases or stashes.
Optional local feature-branch deletion starts unchecked and requires explicit
selection. Squash merges require forced local branch deletion; this is allowed
only after verifying the exact feature tip against the merged PR, and only
after main synchronization succeeds. No other local branches or remote branches
are deleted. If a later step fails, completed synchronization is not undone:
inspect Git before retrying.
Alternatively continue **Check main readiness**, or cancel and use
**Resume after manual PR merge and sync** later.
The release backend freshly fetches
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
It uses GitHub only, with no Forgejo backup or automatic CI certification.
Tests run only when selected, and reported PR checks must be reviewed separately.
The progress indicator shows the current stage, and buttons open GitHub's PR
and release lists. Command results are retained in the shared output panel for
the current dock session, including automatic status refreshes. Output is not
saved across editor restarts and is available only after each command finishes.
While a worker runs, a separate status line displays its operation and elapsed
time. After a minute it explicitly indicates that it is still waiting; this
is not a failure or a claim of incremental progress. No automatic timeout,
cancellation or retry is performed, because remote writes may have completed.
Release operations also display their actual named phase (importing, exporting,
packaging, uploading, downloading, verifying hashes or publishing) through a
private per-command temporary status file, removed after completion. Phases
describe started work, not percentage completion; detailed output still appears
when the command ends. Headless package checks and approved synchronization
also expose their current phase.
Long questions/reviews scroll within the dialog. A failed or malformed status
response clears the old selection/snapshot and stops the guide until refreshed.
Successful Push, Release and Publish operations show a dedicated result dialog
with an **Open on GitHub** link before continuing. Push confirms the branch/PR
but not a merge; Release confirms a verified private draft, not publication;
Publish confirms the exact version was published and links to its release.
The latest result also remains visible in the Guided workflow tab. Failed
publication results never create a success receipt. Successful publication
includes the exact release link, source commit, release ID, publication time,
prerelease/stable status, asset names/hashes, verification and backup status.
Use **Copy result summary** in the result dialog or **Copy last result summary**
in the guide to copy it. This summary lasts for the current dock session.
New publications also save a separate verified receipt under private Git
metadata (`landscaping-releases/last-publication.json`). **View last publication
(saved locally)** loads it after reopening the editor, without contacting GitHub
or repeating publication. It is explicitly historical: remote release state
is not reverified. Existing preparation receipts are never overwritten.
If saving fails after GitHub publishes, a warning reports that distinction;
do not repeat Publish. Releases published before this feature have no saved
publication receipt unless a later publication replaces it.
Failed
operations are marked **NOT CONFIRMED**, because partial remote writes may
need inspection. Closing a success dialog pauses rather than repeating the
completed operation.

### Individual tabs

1. In **Git**, choose **Review and commit** to start the shared file-selection,
   staged-review and naming questions. On main, this asks for a
   `feature/lowercase-kebab-name` branch as part of committing.
   The same reviewed index/HEAD/content guards apply as in Guided workflow.
   After committing, validation is offered; successful validation ends the Git
   step without opening Push. Cancel pauses without undoing the commit.
2. Supporting Git tools can refresh status, inspect tracked/staged diffs,
   stage/unstage whole files or create a branch. Staging changes the real index;
   unstaging keeps working-file edits. Untracked contents and binary assets need
   separate review, especially for credentials and large assets.
3. In **Push**, choose **Push / open PR** for the shared clean-feature-HEAD
   approval. Its result ends this step. Review CI and merge separately on GitHub.
4. In **Release**, choose **Prepare draft release** after synchronizing clean
   main. The shared version/editor question approves a tag and private draft,
   not publication. The result ends this step.
5. Use **Recover existing draft** only for interrupted preparation with a
   retained build; it is a separate recovery utility.
6. In **Publish**, choose **Test and publish verified draft**. Download and
   verify the exact version, test the game and confirm interactive testing,
   then approve the exact publication in its separate final question. Package
   changes invalidate testing approval. The result ends this step.

Commands run in a background thread; output appears when each completes.
Do not disable the plugin or close Godot while a command runs: shutdown waits
for the command and does not cancel remote mutations. The dock never merges
PRs, discards edits, force-pushes, or stores GitHub tokens. Its approved
synchronization action only fast-forwards local main. Authentication
uses the existing `gh` CLI login. Run `gh auth login` in a terminal if needed.

Run [tools/github.ps1](../tools/github.ps1) from PowerShell 5.1 or newer.
It targets `evanmac03/landscaping-planner` on GitHub only. It does not use the
separate os_agent repository's scripts or Forgejo backups.

Prerequisites:

- Git and GitHub CLI (`gh`), authenticated with access to the repository.
- For Release: Godot 4.7.x and matching Windows x86_64 export templates.
  Install templates using Godot's **Editor > Manage Export Templates**.
- A clean, committed checkout for Push, Release, Publish and Synchronize.
  The backend never stages, commits, stashes, rebases, merges PRs or force-pushes.
  Only separately approved Synchronize changes branches/fast-forwards main.

```powershell
# Local information only; safe with uncommitted work.
.\tools\github.ps1

# After creating a feature branch and committing the intended changes:
.\tools\github.ps1 -Action Push -Approve

# Review the PR and GitHub checks, then merge separately.
# From the reviewed clean feature branch, optionally synchronize main:
.\tools\github.ps1 -Action Synchronize -ExpectedHead REVIEWED_SHA -ExpectedBranch feature/my-change -Approve
# Add -CleanupBranch yes only to explicitly delete that verified merged local branch.
# Or switch to main and synchronize it yourself before preparing:
.\tools\github.ps1 -Action Release -Version v0.1.0-rc.1 -Approve

# Optional explicit editor location:
.\tools\github.ps1 -Action Release -Version v0.1.0-rc.1 -Godot 'C:\path\Godot_console.exe' -Approve

# Download and manually test the draft ZIP before this separate approval:
.\tools\github.ps1 -Action Publish -Version v0.1.0-rc.1 -Approve
```

`SmokeTest` accepts `-Package BASE64_JSON -Approve`, where BASE64_JSON is the
UTF-8 base64 encoding of the exact `EDITOR_RESULT` object returned by
`DownloadTest`. It uses that object's executable/folder and file manifest, not
an arbitrary executable path. This action is local and does not authenticate,
fetch, rebuild, upload or publish.

## GitHub CI

[Guided workflow checks](../.github/workflows/workflow-checks.yml) runs on PRs
and pushes to main using Windows runners with PowerShell 5.1 and 7. It installs
Godot 4.7.2 from the official release and verifies a pinned SHA512, then runs
the same focused `Validate` suites. The job has read-only repository permission,
no publishing credentials and no release/export side effects. It is not a
full game playtest or a Windows installer certification.
Checkout uses `actions/checkout@v5` with its supported Node.js 24 runtime.
CI is not active until this workflow is committed/pushed to GitHub; a local
pass must not be presented as a hosted CI pass.

Editor connectivity is separate from these tests. A Godot AI MCP server alone
does not connect this project: it needs a running editor and its compatible
bridge addon enabled. Ziva is a different extension, not that bridge. Installing
or enabling another addon requires a separate setup decision. Rendered automated
guide tests do not certify a manual editor click-through.

## Guarantees and limits

Push fetches origin, rejects remote-only feature commits, pushes the feature
branch and reuses or creates its PR against main. It stops before merge.
It does not run tests or wait for CI; review those separately. Its PR body
explicitly states this limitation.
For newly created PRs, the body includes matching local validation suites and
their UTC timestamp, if a receipt matches the current branch/HEAD/index and
working-file fingerprints. Stale or missing receipts are labelled without
claiming a pass. CI remains a separate, unevaluated gate in that body.
Existing PR descriptions are left unchanged rather than overwritten.

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
