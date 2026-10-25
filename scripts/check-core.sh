#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="${RECORDER_SDK:-$(xcrun --show-sdk-path)}"
if [[ -z "${RECORDER_SDK:-}" && "$(xcode-select -p)" == *CommandLineTools && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
    SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi
mkdir -p .build/core-module-cache
swiftc -swift-version 5 -parse-as-library -sdk "$SDK" -module-cache-path .build/core-module-cache \
  Sources/Recorder/MeetingData.swift Sources/Recorder/PrivateStorage.swift \
  Sources/Recorder/MeetingSummaryService.swift Sources/Recorder/SpeakerNaming.swift \
  Sources/Recorder/OfflineTranscription.swift Sources/Recorder/SpeakerProfile.swift Sources/Recorder/SpeakerProfileStore.swift \
  Sources/Recorder/TranscriptDocument.swift Sources/Recorder/TranscriptLine.swift \
  Sources/Recorder/TranscriptRepository.swift Sources/Recorder/SummaryRepository.swift Sources/Recorder/StereoMixer.swift \
  Sources/Recorder/Shared.swift Sources/Recorder/RecordingsLibrary.swift Sources/Recorder/Preferences.swift \
  Sources/Recorder/AudioHandlingMode.swift Sources/Recorder/WhisperModelOptions.swift Tests/CoreChecks.swift -o .build/recorder-core-checks
.build/recorder-core-checks
