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

Hardened: explicit downloads; local-only tokenizer construction; no automatic identity confirmation; internal/self-only enrollment; customer/roster/version filters; runner-up margin; non-finite and overflow-safe vector comparison; unconfirmed centroids only in RAM; owner-only storage; schema-versioned transcript generations; cancellation checks before result publication; generation guards against old jobs updating new recordings; blockwise resampling/mixing and preservation of the previous complete audio file on error. Pauses write silence on both sources rather than independently compressing their timelines.

No real audio, embeddings or credentials were uploaded during development. Internet requests were dependency/source/model-metadata downloads. Runtime network isolation after model installation is still an explicit acceptance test. Full dependency absence-of-vulnerabilities, model accuracy and biometric matching correctness are not established by this review.
