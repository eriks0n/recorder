# Initial security review — 2026-10-25

Reviewed the initial source revision f1b5c74 before executing project scripts: all Swift sources, package manifest, shell scripts, plist and entitlements. No third-party package dependencies at baseline. No evidence of malicious payloads, command execution from meeting content, telemetry or hidden network destinations found. This is a source review, not a guarantee of absence of vulnerabilities.

Findings addressed in the first implementation steps:
- Cloud transcription was automatic with a stored key. Local processing becomes the default; cloud requires explicit selection.
- Gemini keys in query strings: moved to request headers. Ephemeral sessions, redirects rejected, upload URL restricted to HTTPS Google API host. Server response bodies no longer exposed in errors. Incomplete generations rejected.
- Key replacement deleted the old key before attempting to save: update in place, device-only unlocked accessibility for new keys.
- Menu panel repeatedly initialized permission requests and preferences: initialize once.
- Desktop capture retained pause state across recording sessions: reset on start.
- Sensitive recording directories need explicit owner-only permissions; handled by the local storage work.

Remaining boundaries: non-sandboxed ad-hoc signed app; OS permissions and FileVault remain relevant. Existing files are not retroactively encrypted. Gemini intentionally sends audio and context to Google only when explicitly selected. FluidAudio/MLX and model downloads need separate dependency/model provenance checks. Recording hardware, device transitions, pause alignment and long-session memory require runtime tests. Do not interpret build/unit test success as model quality validation.

## Fork integration follow-up

The user approved cjonesde/recorder and WhisperKit instead of FluidAudio. Gemini/Keychain integration was removed with the adopted base; there is now no cloud transcription adapter. Review source and pinned model provenance: docs/fork-review.md and docs/model-provenance.md.

Hardened: explicit downloads; local-only tokenizer construction; no automatic identity confirmation; explicit profile enrollment; customer/version filters; runner-up margin; non-finite and overflow-safe vector comparison; unconfirmed centroids only in RAM; owner-only storage; schema-versioned transcript generations; cancellation checks before result publication; generation guards against old jobs updating new recordings; blockwise resampling/mixing and preservation of the previous complete audio file on error. Pauses write silence on both sources rather than independently compressing their timelines.

No real audio, embeddings or credentials were uploaded during development. Internet requests were dependency/source/model-metadata downloads. Runtime network isolation after model installation is still an explicit acceptance test. Full dependency absence-of-vulnerabilities, model accuracy and biometric matching correctness are not established by this review.

## Retention and meeting-name extension

Optional retention is disabled by default and only deletes inside recognized recording folders after a complete nonempty transcript has been preserved and verified. Summary files are copied from their authoritative generation before any deletion. Markdown and structured JSON text stay readable; active capture, save, playback, transcription and summary jobs block cleanup. Symlinked text, escaping pointers, malformed/incomplete results and unrelated folders are rejected/skipped. File-name case is handled conservatively so case-insensitive filesystems cannot cause deletion of preserved text. Tests exercise deletion only on unique disposable temporary fixtures. User recordings were not automatically cleaned.

After installation of Xcode/Metal, all 149 XCTest cases ran without failure (12 opted out), including the real local LLM on synthetic German text; the separate 56 core checks also passed. Name/retention/immediate-cleanup functionality has 27 filesystem regression tests. Remaining limitations include real-meeting quality, long-session/device tests, and biometric calibration.

User-requested update: fingerprinting is a complete opt-in switch, covering speaker analysis, embeddings, matching and enrollment. Disabling it unloads stored profiles from memory, invalidates in-flight result tokens and leaves existing profiles on disk for explicit deletion. Categories and calendar-roster restrictions no longer apply; scope/model isolation and human confirmation remain. Eight dedicated fingerprinting tests cover disabled execution, in-flight invalidation, profile storage and generic enrollment.

Immediate audio cleanup is separately opt-in and requires a completed offline transcript plus a matching, validated, saved summary before deleting audio files. Failed/cancelled processing and live recovery transcripts preserve audio. Tests cover stale or invalid summaries, missing text, cancellation and symlink destinations. No user recording was deleted while implementing or testing this option.

## Task inbox and Todoist extension (explicitly authorized)

Durable jobs serialize offline inference, checkpoint the summary stage, and requeue capture-interrupted work. Pending work blocks retention. Inbox data, evidence and receipts are separate from recording cleanup and use owner-only private storage. Corrupt queue/inbox files fail closed instead of being silently overwritten. Export requires reviewed current source, known responsibility and valid dates; cancelled tasks cannot export. Source changes invalidate approval; ambiguous regenerated tasks require explicit duplicate review.

Todoist access is optional. The personal token is stored only in macOS Keychain with device-local accessibility. No token enters task storage, URLs, CSV or logs. The client uses a fixed HTTPS API host, ephemeral sessions and rejects redirects. Only explicit project lookup and confirmed selected-task delivery use the network. Frozen Sync commands and stable UUIDs survive uncertain failures; only a confirmed task ID records success. Definite API/command rejections reopen drafts for correction with fresh approval; uncertain errors remain frozen. CSV batches are durable before writing; formula-leading content is neutralized. CSV import itself is outside the app and must be performed once.

Tests use synthetic text, disposable directories and mocked HTTP responses. No live account tasks are created. Physical capture/end-session timing, long recordings, real Todoist permissions/plan limits and manual CSV import remain acceptance checks. Pending text drafts and receipts are intentionally retained independently from recording audio; deleting a recording is not a complete deletion of its inbox text.

Final extension verification: 179 XCTest cases, 12 hardware/capture cases opted out, zero failures; includes the installed local LLM on synthetic text, three worker scheduling/cancellation tests, ten inbox tests, twelve simulated Todoist/CSV tests and one synthetic offscreen UI render. The independent 56 core checks passed. The UI render injects disposable stores and does not register production launch/retention observers.

## Meeting-scoped own-task delivery

The revised delivery policy permits only reviewed, explicitly selected `mine` tasks in the confirmed meeting. Waiting/unresolved tasks are blocked in the store, selection, CSV and frozen-command preparation, including retries. Global display-name inference is no longer used to infer ownership; meeting-specific speaker IDs or explicit per-task assignment are required. Ambiguous matching display names do not choose a speaker. Source owner changes invalidate previous personal assignments. Shared project assignments are restricted to the connected account; legacy third-party assignees are ignored.

New keys are verified before replacing the Keychain entry. Account identity is checked with the same token snapshot used for task creation; frozen commands are bound to account ID and cannot be retried against a different or unknown account. Meeting-wide settings are atomically persisted, affect only unlocked tasks in that meeting, preserve dates and invalidate approval when changed. Optimistic revisions prevent stale editors from overwriting these settings. Confirmation snapshots are rechecked before each new command. Deleted/inaccessible target projects fail before freezing the command.

Additional synthetic tests cover label normalization, account identity/label endpoints, meeting settings, ownership changes, duplicate names, stale edits, malformed dates, legacy unbound commands, self-assignment and partial batch failures. No live account credentials are used. See meeting-todoist-sync.md for the current workflow and remaining live-account acceptance check.

Final meeting-scoped verification: 197 XCTest cases, 12 hardware/capture cases intentionally skipped, zero failures; 56 separate core checks passed. Eighteen new tests cover meeting delivery and account/ownership edges. Tag parsing also round-trips quoted commas and quotes without silently creating multiple labels. Test API credentials are synthetic; no user account is mutated.
