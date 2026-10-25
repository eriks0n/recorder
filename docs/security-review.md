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
