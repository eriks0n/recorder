# Fork adoption — historical assessment, 2026-10-25

This document records the assessment at adoption. Current behavior and completed work are documented in [README](../README.md). Xcode/Metal and local MLX are now available, code has been pushed to the development branch, and category/calendar filters were superseded by the user's later requirements. The bullets below describe the original changes identified at adoption.

Source: https://github.com/cjonesde/recorder at f1ba832a52ef600d2be94bb549900d42845f1632 (MIT, original copyright retained).

User explicitly approved replacing Parakeet/FluidAudio with WhisperKit and using this fork as the base. Original Parakeet work was copied to /private/tmp/recorder-before-fork before adoption; it was not falsely marked complete. Local Git history retains the initial security commit. This initial assessment preceded the later authorized pushes.

## Reusable implementation

Local WhisperKit/SpeakerKit pipeline, per-channel offline ASR, UI/model loading, structured transcript exports, manual speaker naming, optional voice profiles, realtime capture resampling/device-route fixes, a serialized model host and 111 test methods. Live transcription and transcript-only modes are available but are not required by V1. Prefer retained raw audio and the offline pass for V1.

## Required changes relative to this fork

- Microphone is assumed to be one person (`you`) in OfflineTranscription and is not diarized. Our plan requires diarization of both channels and anonymous labels until confirmation.
- SpeakerNaming compares all profiles globally and only tests an absolute distance. Add customer scope, roster filtering, embedding model compatibility and runner-up margin.
- RecorderModel immediately writes matched names to the transcript. Change to explicit proposals, never identity confirmation by an automatic match.
- Profiles contain no internal/external category. Renaming currently enrolls implicitly when the feature is on. Separate meeting-only naming from explicit internal enrollment.
- Pending centroids persist for up to 30 days even when unconfirmed. Keep them in memory until explicit enrollment.
- Owner-only permissions, local recording folder selection, cancelled processing and complete-result publishing need hardening.
- No LLM summaries or task/evidence validation exist. Add these separately; MLX builds require Xcode/Metal, currently missing on this Mac.
- Package dependency uses a range and Package.resolved was ignored. Pin the dependency and record resolution.

Initial static inspection found no evidence of malicious shell execution, hidden upload endpoints or telemetry in fork-owned source. Dependencies and actual runtime behavior require separate verification. Existing tests have not yet been claimed as passing; model/hardware checks are opt-in and require fixtures.
