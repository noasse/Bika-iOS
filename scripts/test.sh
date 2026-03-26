#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/bika.xcodeproj"
SCHEME_NAME="bika"
TEST_PLAN_NAME="bika"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-Debug}"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/bika-derived}"
RESULTS_DIR="${RESULTS_DIR:-$ROOT_DIR/artifacts/test-results}"
DESTINATION="platform=iOS Simulator,name=${SIMULATOR_NAME},OS=latest"

usage() {
  cat <<'EOF'
用法:
  scripts/test.sh unit            运行单元测试
  scripts/test.sh ui-smoke        运行 UI Smoke
  scripts/test.sh all             先 build-for-testing，再运行 Unit + UI Smoke
  scripts/test.sh build-for-testing
  scripts/test.sh clean           清理 DerivedData 和测试结果

可选环境变量:
  SIMULATOR_NAME       默认 iPhone 17
  DERIVED_DATA_PATH    默认 /tmp/bika-derived
  RESULTS_DIR          默认 <repo>/artifacts/test-results
  BUILD_CONFIGURATION  默认 Debug
EOF
}

ensure_simulator_exists() {
  if ! xcrun simctl list devices available | grep -F "$SIMULATOR_NAME" >/dev/null; then
    echo "未找到可用模拟器: $SIMULATOR_NAME" >&2
    echo "请先安装对应 Simulator Runtime，或用 SIMULATOR_NAME 覆盖。" >&2
    exit 1
  fi
}

resolve_simulator_udid() {
  xcrun simctl list devices available | awk -v device="$SIMULATOR_NAME" '
    index($0, device " (") {
      count = split($0, parts, /[()]/)
      if (count >= 3) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", parts[2])
        print parts[2]
        exit
      }
    }
  '
}

prepare_ui_simulator() {
  local simulator_udid
  simulator_udid="$(resolve_simulator_udid)"

  if [[ -z "$simulator_udid" ]]; then
    echo "无法解析模拟器 UDID: $SIMULATOR_NAME" >&2
    exit 1
  fi

  xcrun simctl shutdown "$simulator_udid" >/dev/null 2>&1 || true
  xcrun simctl boot "$simulator_udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$simulator_udid" -b
  xcrun simctl terminate "$simulator_udid" com.noasse.bika >/dev/null 2>&1 || true
  xcrun simctl terminate "$simulator_udid" com.noasse.bikaUITests.xctrunner >/dev/null 2>&1 || true
}

prepare_directories() {
  mkdir -p "$RESULTS_DIR"
}

run_xcodebuild() {
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME_NAME" \
    -testPlan "$TEST_PLAN_NAME" \
    -configuration "$BUILD_CONFIGURATION" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    "$@"
}

build_for_testing() {
  ensure_simulator_exists
  prepare_directories
  run_xcodebuild build-for-testing
}

run_unit_without_building() {
  rm -rf "$RESULTS_DIR/unit.xcresult"
  run_xcodebuild \
    test-without-building \
    -only-test-configuration Unit \
    -only-testing:bikaTests \
    -resultBundlePath "$RESULTS_DIR/unit.xcresult"
}

run_ui_smoke_without_building() {
  prepare_ui_simulator
  rm -rf "$RESULTS_DIR/ui-smoke.xcresult"
  run_xcodebuild \
    test-without-building \
    -only-test-configuration "UI Smoke" \
    -only-testing:bikaUITests \
    -resultBundlePath "$RESULTS_DIR/ui-smoke.xcresult"
}

run_unit() {
  build_for_testing
  run_unit_without_building
}

run_ui_smoke() {
  build_for_testing
  run_ui_smoke_without_building
}

run_all() {
  build_for_testing
  run_unit_without_building
  run_ui_smoke_without_building
}

clean_outputs() {
  rm -rf "$DERIVED_DATA_PATH" "$RESULTS_DIR"
}

COMMAND="${1:-all}"

case "$COMMAND" in
  unit)
    run_unit
    ;;
  ui-smoke)
    run_ui_smoke
    ;;
  all)
    run_all
    ;;
  build-for-testing)
    build_for_testing
    ;;
  clean)
    clean_outputs
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage
    exit 1
    ;;
esac
