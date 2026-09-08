#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
experiment_phase="${1:-retrieval}"
case "$experiment_phase" in
  retrieval) experiment_test=testRetrievalMatrix ;;
  inference) experiment_test=testInferenceMatrix ;;
  cache) experiment_test=testPromptCacheMatrix ;;
  batches) experiment_test=testPrefillBatchMatrix ;;
  answers) experiment_test=testGroundedAnswerMatrix ;;
  files) experiment_test=testImportedFileAnswerMatrix ;;
  *) echo 'Usage: bash scripts/run-experiments.sh {retrieval|inference|cache|batches|answers|files}' >&2; exit 2 ;;
esac
if [ -z "${THIMVALE_SIMULATOR_ID:-}" ]; then
  THIMVALE_SIMULATOR_ID=$(xcrun simctl list devices available -j | jq -r '[.devices | to_entries[] | select(.key | endswith("iOS-26-1")) | .value[] | select(.name == "iPhone 17 Pro")][0].udid // empty')
fi
if [ -z "$THIMVALE_SIMULATOR_ID" ]; then echo 'Install the iOS 26.1 iPhone 17 Pro simulator first.' >&2; exit 1; fi
xcodegen generate
xcrun simctl bootstatus "$THIMVALE_SIMULATOR_ID" -b
mkdir -p TestResults
experiment_result="TestResults/Experiment-$experiment_phase-$(date -u +%Y%m%dT%H%M%SZ)"
xcodebuild test -project Thimvale.xcodeproj -scheme ThimvaleExperiments \
  -destination "platform=iOS Simulator,id=$THIMVALE_SIMULATOR_ID" -derivedDataPath build \
  -parallel-testing-enabled NO -only-testing:"ThimvaleIntegrationTests/ExperimentTests/$experiment_test" \
  -resultBundlePath "$experiment_result.xcresult" CODE_SIGNING_ALLOWED=NO \
  2>&1 | tee "$experiment_result.log"
