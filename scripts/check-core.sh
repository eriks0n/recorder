#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="${RECORDER_SDK:-$(xcrun --show-sdk-path)}"
mkdir -p .build/core-module-cache
swiftc -swift-version 5 -parse-as-library -sdk "$SDK" -module-cache-path .build/core-module-cache \
  Sources/Recorder/MeetingData.swift Sources/Recorder/PrivateStorage.swift \
  Sources/Recorder/MeetingSummaryService.swift Sources/Recorder/SpeakerNaming.swift \
  Sources/Recorder/SpeakerProfile.swift Sources/Recorder/SpeakerProfileStore.swift \
  Sources/Recorder/TranscriptDocument.swift Sources/Recorder/TranscriptLine.swift \
  Sources/Recorder/TranscriptRepository.swift Tests/CoreChecks.swift -o .build/recorder-core-checks
.build/recorder-core-checks
