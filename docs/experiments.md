# Experiment and Knowledge Management

## 1. Scope and Operating Model

This policy covers experiments in project `scratch/` directories and dedicated external temporary roots. Its purpose is to make experimental workspaces identifiable and manageable throughout their lifecycle, so artifacts can be resumed, retained, or safely cleaned up while protecting original inputs, useful knowledge, and required evidence.

| Location | Purpose |
|---|---|
| `scratch/` | Isolated experiments, exploratory scripts, inputs, outputs, and recovery records; disposable artifacts stay out of Git |
| `tests/` | Reusable executable checks for intended behavior, invariants, regressions, and important edge cases |
| `note/` | Durable explanations, conclusions, limitations, and decisions |

Use established project locations where they differ. Adapt to the language and build system, and create directories only when needed. Each experiment directory represents one investigation and one lifecycle unit.

### Stage-Scoped Instructions

Read the policy once to understand its structure. Then apply the common safeguards below and the current stage's section. Responsibilities in other stages are deferred, not a checklist to plan or maintain in parallel.

| Stage | Focus now | Transition |
|---|---|---|
| Initialization (§2) | Establish the question, workspace, inputs, and minimal recovery context | Begin work when the first meaningful experimental action can start |
| Work (§3) | Investigate, validate results, and capture evidence that could be lost | Enter summary at a useful stopping point, including failure or requested handoff |
| Summary (§4) | Briefly report findings, agree on any additional durable deliverables, and decide retention | Return to work if a substantive uncertainty needs investigation; do not reinitialize |

Transitions require no additional approval or tracking file. When metadata is used, update `stage` at meaningful transitions and handoffs; otherwise record it in existing recovery records only when useful. It identifies the last confirmed instructional focus, not process activity. Experiment outcome, durable preservation, and workspace retention are separate decisions.

Metadata and recovery records describe last-confirmed facts and decisions, not live status. Abrupt termination may leave them unchanged; no final checkpoint or `interrupted` state can be guaranteed. Reconcile them with actual evidence before reuse. User-requested workspace review follows §5 as a separate maintenance task, not a fourth experiment stage.

A deliverable that directly supports the current investigation or is requested now may be produced in any stage. Validation needed to trust a result belongs in work; packaging that validation as a maintained test normally belongs in summary.

### Common Safeguards

Apply these throughout the lifecycle:

- Modify only experiments created by or assigned to the task, unless coordination establishes broader authority. Protect other active tasks' work and synchronize shared edits; use external ownership and locking mechanisms when available.
- Preserve original user inputs and unknown artifacts until their roles and disposal authority are established. Completion alone does not authorize deleting inputs.
- Capture evidence before it is lost. Keep provenance truthful, distinguish observations from verified conclusions, and keep secrets out of records.
- Before any deletion, apply §4's cleanup checks, even if deleting during another stage.

### Record Only What the Experiment Needs

Every independent experiment directory needs minimal local context: its purpose and whether it contains original inputs, identifying their source or marking it unknown. A line in an existing script or log may suffice; create a small record only if needed. A trivial disposable check can leave its command and outcome in the task report. Do not create metadata, README, and journal files merely to complete a template.

For nontrivial, retained, or resumable experiments, use:

- `metadata.json` for identity, baseline, and lifecycle decisions.
- `README.md` for a concise current-state snapshot and evidence pointers.
- `journal.md` for selected changes that matter to later decisions or recovery, when the README and existing logs are insufficient.

Create these when needed and keep them brief. Records must be sufficient for recovery before an experiment is left for later use.

## 2. Initialization

Identify the question, requested result, and available inputs. Create or adopt a workspace and record enough context to begin; final conclusions and polished reproduction instructions can wait.

### Workspace Identity

Prefer project `scratch/`. Outside the repository, use a dedicated per-user temporary root, such as `/tmp/ai-$USER/$project/`, with restrictive permissions where appropriate. Do not scatter artifacts across the project root or directly across `/tmp`. System temporary storage may be removed during reboot or maintenance; preserve valuable work in storage suited to its recovery needs.

Name each independent experiment directory:

```text
YYYYMMDD-HHMM-topic-commitid-uniqueid/
```

- Use the creation or adoption time, with the timezone in records.
- Choose a short topic and an abbreviated Git HEAD hash (normally 8–12 characters), or `nogit` when unavailable.
- Generate an independent random identifier: the commit identifies a baseline, not an experiment instance.

Allocate new directories atomically, for example with `mktemp -d`. Related steps may share a directory; a substantially different objective needs a new one. Keep inputs, scripts, outputs, and evidence together, adding subdirectories only as needed. Do not reuse another active experiment's workspace.

Write the minimal local context immediately after allocation, before experimental work. If interrupted before this record exists, later review must treat the directory as unidentified rather than infer that it is disposable.

### Adopt a User-Prepared Directory

When the user supplies a directory under a managed scratch root for processing, adopt it before processing:

1. **Inspect and preserve minimal provenance.** Establish scope and relevant active use. Do not adopt the scratch root, unrelated siblings, or a symlink target outside the authorized workspace. If records identify an existing experiment, use §3's recovery procedure instead of renaming or resetting it. Before renaming, leave its original path, purpose, and identification of supplied inputs in a local record; reuse existing records or use a nonconflicting filename. This record must move with the directory.
2. **Normalize its name.** Rename the whole directory within the same managed root using the convention above and an operation that fails if the destination exists. On collision, generate another identifier. Preserve its contents; do not substitute copy-and-delete, restructure inputs, or create compatibility symlinks automatically. If safe renaming is blocked by active use or filesystem constraints, retain the directory and report why.
3. **Complete provenance.** Extend the pre-rename record with the normalized path, input inventory, observed Git baseline, and next action. Identify pre-existing inputs separately from generated outputs; whole input subdirectories may serve as inventory entries. Preserve existing user files and create only needed records. Append an `INITIALIZED` entry if a journal is used.
4. **Report the normalized path and proceed.** Update known references within the authorized task when needed; do not search and rewrite unrelated project files.

Adoption authorizes directory normalization and necessary record creation within the assigned task. Input modification or deletion still requires authorization from the processing task or an applicable user-established policy. Retain directories containing original inputs at completion unless their disposal is authorized.

Keep the normalized identity stable across later handoffs. The adoption timestamp and observed Git revision do not establish when or how the supplied data was produced; record its known provenance separately and mark unavailable provenance as unknown.

### Metadata for Retained or Resumable Work

Use ISO 8601 timestamps with explicit timezone offsets. Record these fields when metadata is warranted:

| Fields | Meaning |
|---|---|
| `id`, `purpose` | Stable directory name and experimental question |
| `owner`, `task_id` | Original preparer and logical task; neither proves exclusive ownership or activity |
| `created_at`, `updated_at` | Creation of the managed experiment record and latest metadata update |
| `git_commit`, `git_branch`, `git_dirty` | Full initial HEAD hash, branch, and presence of tracked changes or non-ignored untracked files; use `null` where unknown or inapplicable |
| `stage` | Last confirmed stage: `initialization`, `work`, or `summary`; no separate done or waiting-for-user stage |
| `outcome` | `null` until a stopping-point assessment; then `conclusive`, `inconclusive`, or `failed`, as defined below |
| `knowledge_status` | `pending` until the durable-preservation decision and any selected work are complete; then `not_selected` or `preserved` |
| `knowledge_paths` | Verified durable destinations; start with `[]` and add only actual, checked paths |
| `retention` | Workspace disposition: `temporary` by default, `archived` when intentionally retained as an archive, or `disposable` after an authorized disposal decision; always subject to cleanup checks |

For user-prepared work, also record `workspace_origin: "user_prepared"`, `managed_by`, `initialized_at`, `original_path`, and `initial_inputs`. Identify the user as the original preparer where known; do not claim the agent created supplied files. Preserve earlier creation history separately. Use actual session identifiers only when available.

Outcome values describe the investigation, not whether summary or cleanup is finished:

| Outcome | Meaning |
|---|---|
| `null` | No final outcome has been assessed for the current investigation |
| `conclusive` | The question has a supported answer, including a negative result |
| `inconclusive` | Work stopped without enough evidence to answer the question |
| `failed` | An execution or setup failure prevented the investigation from proceeding sufficiently to assess the question |

`knowledge_status: not_selected` means the preservation assessment is complete and no additional durable deliverable was selected; it does not mean the experiment has no value or that scratch may be deleted. `preserved` means all selected deliverables have been saved and verified. Keep it `pending` while a decision or selected work remains outstanding; record partial exports in `knowledge_paths` as they are verified. A failed or inconclusive experiment may still have preserved knowledge.

For example, after reporting a supported answer while awaiting a preservation decision, use `stage: summary`, `outcome: conclusive`, `knowledge_status: pending`, and `retention: temporary`. Once summary is finished, `stage` may remain `summary`; do not add a global completion flag merely to duplicate these fields.

Do not create a commit to initialize metadata. A Git baseline and dirty flag do not preserve uncommitted source: retain relevant diffs, inputs, or a minimal snapshot when these affect the result or its reproduction. Preserve the initial Git fields; record intentional revision changes and their source state in the journal or equivalent recovery record. Replace metadata atomically where practical.

## 3. Work

Focus on answering the question: inspect inputs, run calculations, compare alternatives, debug, and test hypotheses. Perform checks needed to trust the current result now, including analytical comparisons, convergence checks, and assertions.

Keep exploratory checks in the experiment workspace unless the task or project workflow requires maintained tests now. Write scripts when they help the investigation; a separate reproduction runner is optional.

Capture information that is expensive or impossible to reconstruct: important commands, parameters, seeds, relevant environment details, input versions, and evidence paths. Prefer existing outputs, scripts, and run logs; link to them rather than duplicating their contents in prose records. Capture necessary evidence when it is produced; batch narrative updates at meaningful stopping points.

### Current State and Checkpoints

Treat the README, when used, as a snapshot, not a cumulative report. Keep only the current goal and method, verified state, unresolved blockers, key evidence pointers, and next action. Replace obsolete state instead of appending progress; move still-useful history to the journal only if it meets the criteria below. Aim for a brief overview that can be read without tracing the investigation's history.

Add a journal entry only when it preserves a consequential change of direction with supporting evidence, a finding or failure needed to avoid repeating work, or recovery context not already available elsewhere. Combine related attempts into one entry: what changed, the supporting evidence path, and its implication for the next step. Include a timestamp and distinguish hypotheses from verified findings. Omit routine commands, repeated unchanged failures, and progress already recoverable from logs or the README. Preserve recorded history and append corrections; event labels are optional.

Before long-running, destructive, or difficult-to-reproduce operations, preserve missing recovery context, including the intended action and how to locate its state and outputs. At handoff, controlled pause, or a meaningful change of approach, update the current-state snapshot; add a journal checkpoint only if it preserves information the snapshot and existing logs cannot. Abrupt termination is handled by recovery, not an assumed final update. Elapsed time or command count alone does not justify an entry. Record actions and evidence, not internal reasoning transcripts.

### Recovery

Before resuming or modifying a previous experiment, establish ownership or coordination, then:

1. Read its available metadata, overview, and relevant checkpoints.
2. Inspect actual files, partial outputs, and relevant process activity; the last recorded intention may not have completed.
3. Check any partly promoted tests or notes, their authorization, and outstanding preservation decisions; reconcile discrepancies.
4. Reconcile records with the recovered state and uncertainties, then resume the appropriate stage or decide retention. If substantive investigation resumes, reset `outcome` to `null` and `knowledge_status` to `pending`; reassess preservation for the new work without dropping verified destinations. Add a recovery entry only if it reveals a material discrepancy or adds necessary context; an unchanged resume needs no journal entry.

Continue from the last verified state. When an operation's completion was not recorded, treat its result as unverified until checked; missing records do not prove it failed or did not run. Inspect partial results and possible side effects before retrying operations or using their outputs.

Recorded stage, outcome, retention, directory age, stale heartbeat, PID alone, or agent-written records cannot reliably prove inactivity. Processes may outlive their manager. Do not claim supervision, locking, automatic recovery, or safe garbage collection exists unless an actual mechanism provides it. Interpret older `status` and `knowledge_exported` fields against actual evidence when resuming; do not infer preservation or disposal authority from their names or values.

## 4. Summary

Begin with a brief report of what was verified, what failed, and what remains uncertain. Reporting does not require a new document, an expanded README, a complete experiment history, or a reproduction package. Keep necessary recovery records current; do not polish them merely because work has stopped.

### Decide Whether to Preserve More

Choose handling by future use and the maintenance it justifies, not as a ladder of increasing importance. The four common options below may be combined; reporting a result does not decide whether its scratch materials are retained or deleted. Archive is an additional option for original evidence. Do not classify every artifact or produce a separate assessment report.

| Handling | Appropriate use | Responsibility |
|---|---|---|
| Task report only | One-off answers and routine verification with no continuing use | No additional summary file to maintain; workspace retention is decided separately |
| Existing scratch workspace | Exploratory scripts, raw outputs, and evidence whose future value is uncertain or does not justify maintenance | Keep enough context to locate, interpret, and resume retained work; do not promise indefinite preservation |
| `tests/` | Behavior, invariants, regressions, or important edge cases the project should keep checking | Keep checks runnable and their expected behavior justified as the project changes |
| `note/` | Explanations, conclusions, decisions, limitations, and justified rejected approaches worth consulting later | Keep conclusions accurate and scoped, and avoid duplicate or conflicting explanations |
| Archive | Original evidence whose durable value cannot be replaced by tests or notes | Preserve evidence in storage suited to its intended retention, with provenance and recovery pointers |

Leave low-value or uncertain artifacts in scratch rather than promoting them for tidiness. Tests create a maintenance commitment; they are not a miscellaneous storage area. An important finding may need a test, a note, or retained evidence, but not all three.

When additional durable preservation is worth considering, briefly propose the specific finding, smallest useful destination, its expected future use, and the maintenance it would require. Ask the user to choose before preparing or promoting those additional deliverables. Do not prepare full notes or packages just to ask whether they are wanted. If the task or an established user policy already authorizes the relevant deliverables, complete them without asking again. Necessary validation and capture of evidence that could be lost remain work-stage responsibilities and must not wait for this decision.

If nothing warrants additional preservation, finish with the brief report; no question or summary file is needed. If the user chooses report only or scratch retention, do not add tests or notes. While a decision is pending, retain the workspace and enough recovery context to resume; do not treat silence as approval for promotion or disposal.

### Preserve Selected Deliverables

Use the smallest adequate representation for the selected, authorized work. Reuse or update an existing destination when appropriate instead of creating overlapping records.

Review exploratory checks before promoting them. Use meaningful assertions, justified expected values, and appropriate tolerances; prefer deterministic tests. Do not turn incidental outputs, bugs, or unverified assumptions into requirements. Label characterization tests and state whether the observed behavior should be preserved.

Integrate selected tests with the project's existing test workflow where appropriate; document how to run standalone checks. This does not require introducing new CI infrastructure.

For selected notes, prefer updating an existing relevant explanation. Include the evidence sources, applicable conditions, and limitations needed to interpret the conclusion. When later authorized work changes that conclusion, revise the relevant note and reconcile conflicting statements rather than adding a duplicate explanation. This is a maintenance obligation when affected, not a requirement for recurring reviews.

When deliverables are selected:

1. Create or update the chosen destinations.
2. Verify their contents and run checks needed for new or changed tests. Reuse sufficient verification already performed; repeat expensive work only to resolve a concrete uncertainty.
3. Record verified paths and set `knowledge_status` to `preserved` only when all selected work is complete, if metadata is used.

If no additional durable deliverable is selected, set `knowledge_status` to `not_selected` in existing metadata after the assessment or user decision. A brief reason in an existing record is enough; do not create a separate assessment document. Keep it `pending` if anything remains undecided or unfinished. Preservation decisions do not authorize disposal.

Selected durable project findings belong in tests, notes, or retained evidence; `AGENTS.md` and this policy contain stable rules, not experiment history.

### Reproduction Materials

Include reproduction materials only when selected or already requested and repeated execution or handoff justifies maintaining them. Prefer an existing script or test, or a clear command in an existing record. `reproduce.sh` is an option, not a required file.

Assemble any needed runner from the validated workflow. Preserve required inputs and environment assumptions, verify what the handoff requires, and state what was actually run and any limitations. Preserve dependencies in stable locations before deleting scratch; claim reproducibility only to the extent supported by evidence.

### Retention and Cleanup

Return to work if needed; otherwise decide temporary retention, archival, or disposal separately from the experiment outcome and durable deliverables. Update existing records with the outcome, retained evidence, next action if needed, and actual decisions. Ensure anything left for later use has enough recovery context. If ownership, activity, or value is uncertain, retain it temporarily for review. Temporary retention does not require promoting the contents or setting a speculative expiry date.

Keep any existing README concise. Reorganize accumulated history only when it materially improves recovery or is requested; preserve original journal entries and provide brief evidence pointers as needed. Do not discard unique evidence or corrections to meet a length target. Routine work does not require maintaining a second history summary.

Clean up disposable experiments created by or assigned to the task when safe. Evaluate each directory as a lifecycle unit rather than dismantling evidence from an unevaluated experiment.

Before deleting an experiment, verify:

- The resolved target is the intended experiment directory inside a known managed scratch root, not the root itself, and deletion cannot affect outside paths.
- Ownership or cleanup authority is established and no relevant active task or process is using it.
- An explicit disposal decision or applicable cleanup policy authorizes disposal, including any original user inputs.
- Valuable knowledge and required evidence have been preserved, or their disposal has been explicitly judged acceptable. Declining additional tests or notes does not by itself make original evidence disposable.
- Relevant tests, notes, scripts, and retained deliverables no longer require files in this workspace. Exported paths alone do not prove these dependencies were removed.

Coordinate with other possible users before deletion and recheck activity if the situation may have changed since inspection. Where concurrent reuse is possible, use an actual shared exclusion mechanism; an earlier check or agent-written ownership field does not prevent a new user from entering. If safe exclusion cannot be established, retain the directory.

Do not follow symlinks outside the managed root or use broad recursive deletion with unchecked paths. Age, stage, outcome, retention expiry, and a completed preservation assessment alone do not authorize deletion. A separate cleanup mechanism must independently establish the same conditions; prefer retention and recovery review when uncertain.

### Git and Completion Report

Track durable tests, notes, `AGENTS.md`, and this policy according to the existing Git workflow. This does not authorize creating commits or pushing.

To track an otherwise empty scratch directory, use `scratch/.gitignore`:

```gitignore
*
!.gitignore
```

Promote valuable artifacts to tracked locations instead of committing whole temporary workspaces. Ignore rules neither untrack existing files nor protect secrets.

Keep the completion report brief: findings and verification, remaining uncertainties, deliverables actually produced, cleanup actually performed, and retained experiment paths with reasons or pending decisions where needed. Include only applicable items and report material changes since an earlier summary without repeating the full history. Do not claim actions that did not occur or require scratch to be perfectly empty.

## 5. Review and Cleanup

Run this maintenance task when the user requests review or cleanup of managed scratch workspaces. It does not require a standing reviewer, background monitor, heartbeat, or new per-experiment state fields.

1. Establish the requested roots, scope, and disposal authority. Inspect directories without resetting their identity or inferring disposal authority from their names. Age may prioritize review, but cannot decide deletion.
2. Compare available records with actual files, partial outputs, relevant tasks and processes (including jobs that outlive an agent session), and external dependencies. Apply §3's recovery checks as needed; record missing evidence as uncertainty.
3. Classify each directory for this review using the table below. Keep previous decisions distinct from current observations; these categories belong in the review report, not new metadata fields.
4. Perform only authorized actions that satisfy §4's cleanup checks. Briefly report what was removed, retained paths and reasons, and concrete unresolved decisions. Update existing records only for verified corrections or actual decisions; a separate report file is optional.

| Current observation | Handling |
|---|---|
| Confirmed in use | Retain and avoid interfering with active work |
| Recoverable work or an outstanding decision | Retain and identify the next action or decision |
| All cleanup conditions satisfied | Delete within the granted scope, or propose the specific disposal if not authorized |
| Unknown provenance, activity, or value | Retain and identify what evidence or authority is missing |

A review request authorizes inspection and recommendations. An explicit cleanup request or established user cleanup policy authorizes qualifying disposal within its scope, without asking again for each directory. Neither overrides protection of active work, original inputs without disposal authority, required dependencies, or unresolved uncertainty. Do not convert missing completion records or absent visible processes into `failed`, `inconclusive`, or permission to delete.
