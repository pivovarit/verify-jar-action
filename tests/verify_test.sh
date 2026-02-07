#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFY_SH="$(cd "$SCRIPT_DIR/.." && pwd)/verify.sh"
WORK_DIR=""
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

setup() {
  WORK_DIR=$(mktemp -d)
}

teardown() {
  [ -n "$WORK_DIR" ] && rm -rf "$WORK_DIR"
}

pass() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo "  PASS: $1"
}

fail() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo "  FAIL: $1"
  echo "        $2"
}

run_verify() {
  INPUT_DIRECTORY="${1}" \
  INPUT_BYTECODE_VERSION="${2}" \
  INPUT_MAX_CHECKS="${3:-0}" \
  bash "$VERIFY_SH" 2>&1
}

build_jar_with_release() {
  local release="$1"
  local jar_name="$2"
  local src_dir="$WORK_DIR/src"
  mkdir -p "$src_dir"
  echo 'public class Hello { }' > "$src_dir/Hello.java"
  javac --release "$release" -d "$src_dir" "$src_dir/Hello.java"
  jar cf "$WORK_DIR/$jar_name" -C "$src_dir" Hello.class
  rm -rf "$src_dir"
}

build_jar_no_classes() {
  local jar_name="$1"
  local content_dir="$WORK_DIR/content"
  mkdir -p "$content_dir"
  echo "hello" > "$content_dir/readme.txt"
  jar cf "$WORK_DIR/$jar_name" -C "$content_dir" readme.txt
  rm -rf "$content_dir"
}

build_jar_multiple_classes() {
  local release="$1"
  local jar_name="$2"
  local src_dir="$WORK_DIR/src"
  mkdir -p "$src_dir"
  echo 'public class A { }' > "$src_dir/A.java"
  echo 'public class B { }' > "$src_dir/B.java"
  echo 'public class C { }' > "$src_dir/C.java"
  javac --release "$release" -d "$src_dir" "$src_dir/A.java" "$src_dir/B.java" "$src_dir/C.java"
  jar cf "$WORK_DIR/$jar_name" -C "$src_dir" A.class -C "$src_dir" B.class -C "$src_dir" C.class
  rm -rf "$src_dir"
}

test_directory_does_not_exist() {
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "TEST: directory does not exist"
  setup

  output=$(run_verify "$WORK_DIR/nonexistent" "52" "0" || true)

  if echo "$output" | grep -q "does not exist"; then
    pass "reports missing directory"
  else
    fail "should report missing directory" "output: $output"
  fi

  # verify non-zero exit
  if INPUT_DIRECTORY="$WORK_DIR/nonexistent" INPUT_BYTECODE_VERSION="52" INPUT_MAX_CHECKS="0" bash "$VERIFY_SH" >/dev/null 2>&1; then
    fail "should exit with non-zero" ""
  else
    pass "exits with non-zero"
  fi

  teardown
}

test_no_jar_files() {
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "TEST: no JAR files in directory"
  setup

  output=$(run_verify "$WORK_DIR" "52" "0" || true)

  if echo "$output" | grep -q "No .jar files"; then
    pass "reports no JAR files"
  else
    fail "should report no JAR files" "output: $output"
  fi

  if INPUT_DIRECTORY="$WORK_DIR" INPUT_BYTECODE_VERSION="52" INPUT_MAX_CHECKS="0" bash "$VERIFY_SH" >/dev/null 2>&1; then
    fail "should exit with non-zero" ""
  else
    pass "exits with non-zero"
  fi

  teardown
}

test_compliant_jar() {
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "TEST: compliant JAR (version <= threshold)"
  setup

  build_jar_with_release 8 "good.jar"

  if output=$(run_verify "$WORK_DIR" "52" "0"); then
    pass "exits with zero"
  else
    fail "should exit with zero" "output: $output"
  fi

  if echo "$output" | grep -q "major version"; then
    pass "reports major version"
  else
    fail "should report major version" "output: $output"
  fi

  teardown
}

test_non_compliant_jar() {
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "TEST: non-compliant JAR (version > threshold)"
  setup

  build_jar_with_release 17 "bad.jar"

  output=$(run_verify "$WORK_DIR" "52" "0" || true)

  if echo "$output" | grep -q "exceeds allowed"; then
    pass "reports exceeds allowed"
  else
    fail "should report exceeds allowed" "output: $output"
  fi

  if INPUT_DIRECTORY="$WORK_DIR" INPUT_BYTECODE_VERSION="52" INPUT_MAX_CHECKS="0" bash "$VERIFY_SH" >/dev/null 2>&1; then
    fail "should exit with non-zero" ""
  else
    pass "exits with non-zero"
  fi

  teardown
}

test_jar_no_class_files() {
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "TEST: JAR with no class files"
  setup

  build_jar_no_classes "empty.jar"

  if output=$(run_verify "$WORK_DIR" "52" "0"); then
    pass "exits with zero"
  else
    fail "should exit with zero" "output: $output"
  fi

  if echo "$output" | grep -q "skipping"; then
    pass "reports skipping"
  else
    fail "should report skipping" "output: $output"
  fi

  teardown
}

test_max_checks_limits_inspection() {
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "TEST: max-checks limits inspection count"
  setup

  build_jar_multiple_classes 8 "multi.jar"

  output=$(run_verify "$WORK_DIR" "52" "1")
  checked=$(echo "$output" | grep -c "major version" || true)

  if [ "$checked" -eq 1 ]; then
    pass "only 1 class checked with max-checks=1"
  else
    fail "expected 1 class checked, got $checked" "output: $output"
  fi

  teardown
}

test_multiple_jars_mixed_compliance() {
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "TEST: multiple JARs, mixed compliance"
  setup

  build_jar_with_release 8 "good.jar"
  build_jar_with_release 17 "bad.jar"

  output=$(run_verify "$WORK_DIR" "52" "0" || true)

  if echo "$output" | grep -q "exceeds allowed"; then
    pass "reports non-compliant JAR"
  else
    fail "should report non-compliant JAR" "output: $output"
  fi

  if INPUT_DIRECTORY="$WORK_DIR" INPUT_BYTECODE_VERSION="52" INPUT_MAX_CHECKS="0" bash "$VERIFY_SH" >/dev/null 2>&1; then
    fail "should exit with non-zero" ""
  else
    pass "exits with non-zero"
  fi

  teardown
}

echo "Running verify.sh tests..."
echo ""

test_directory_does_not_exist
test_no_jar_files
test_compliant_jar
test_non_compliant_jar
test_jar_no_class_files
test_max_checks_limits_inspection
test_multiple_jars_mixed_compliance

echo ""
echo "========================================="
echo "Tests run: $TESTS_RUN"
echo "Passed:    $TESTS_PASSED"
echo "Failed:    $TESTS_FAILED"
echo "========================================="

if [ "$TESTS_FAILED" -gt 0 ]; then
  exit 1
fi
