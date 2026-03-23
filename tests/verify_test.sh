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
  INPUT_JAVA_VERSION="${2:-}" \
  INPUT_BYTECODE_VERSION="${3:-}" \
  INPUT_MAX_CHECKS="${4:-0}" \
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

  output=$(run_verify "$WORK_DIR/nonexistent" "" "52" "0" || true)

  if echo "$output" | grep -q "does not exist"; then
    pass "reports missing directory"
  else
    fail "should report missing directory" "output: $output"
  fi

  # verify non-zero exit
  if INPUT_DIRECTORY="$WORK_DIR/nonexistent" INPUT_JAVA_VERSION="" INPUT_BYTECODE_VERSION="52" INPUT_MAX_CHECKS="0" bash "$VERIFY_SH" >/dev/null 2>&1; then
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

  output=$(run_verify "$WORK_DIR" "" "52" "0" || true)

  if echo "$output" | grep -q "No .jar files"; then
    pass "reports no JAR files"
  else
    fail "should report no JAR files" "output: $output"
  fi

  if INPUT_DIRECTORY="$WORK_DIR" INPUT_JAVA_VERSION="" INPUT_BYTECODE_VERSION="52" INPUT_MAX_CHECKS="0" bash "$VERIFY_SH" >/dev/null 2>&1; then
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

  if output=$(run_verify "$WORK_DIR" "" "52" "0"); then
    pass "exits with zero"
  else
    fail "should exit with zero" "output: $output"
  fi

  if echo "$output" | grep -q "Checked"; then
    pass "reports checked class count"
  else
    fail "should report checked class count" "output: $output"
  fi

  teardown
}

test_non_compliant_jar() {
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "TEST: non-compliant JAR (version > threshold)"
  setup

  build_jar_with_release 17 "bad.jar"

  output=$(run_verify "$WORK_DIR" "" "52" "0" || true)

  if echo "$output" | grep -q "exceeds allowed"; then
    pass "reports exceeds allowed"
  else
    fail "should report exceeds allowed" "output: $output"
  fi

  if INPUT_DIRECTORY="$WORK_DIR" INPUT_JAVA_VERSION="" INPUT_BYTECODE_VERSION="52" INPUT_MAX_CHECKS="0" bash "$VERIFY_SH" >/dev/null 2>&1; then
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

  if output=$(run_verify "$WORK_DIR" "" "52" "0"); then
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

  output=$(run_verify "$WORK_DIR" "" "52" "1")
  checked=$(echo "$output" | grep -oE 'Checked [0-9]+' | awk '{print $2}' || true)

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

  output=$(run_verify "$WORK_DIR" "" "52" "0" || true)

  if echo "$output" | grep -q "exceeds allowed"; then
    pass "reports non-compliant JAR"
  else
    fail "should report non-compliant JAR" "output: $output"
  fi

  if INPUT_DIRECTORY="$WORK_DIR" INPUT_JAVA_VERSION="" INPUT_BYTECODE_VERSION="52" INPUT_MAX_CHECKS="0" bash "$VERIFY_SH" >/dev/null 2>&1; then
    fail "should exit with non-zero" ""
  else
    pass "exits with non-zero"
  fi

  teardown
}

test_java_version_compliant() {
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "TEST: java-version compliant JAR"
  setup

  build_jar_with_release 8 "good.jar"

  if output=$(run_verify "$WORK_DIR" "8" "" "0"); then
    pass "exits with zero"
  else
    fail "should exit with zero" "output: $output"
  fi

  teardown
}

test_java_version_non_compliant() {
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "TEST: java-version non-compliant JAR"
  setup

  build_jar_with_release 17 "bad.jar"

  output=$(run_verify "$WORK_DIR" "8" "" "0" || true)

  if echo "$output" | grep -q "exceeds allowed"; then
    pass "reports exceeds allowed"
  else
    fail "should report exceeds allowed" "output: $output"
  fi

  teardown
}

test_java_version_overrides_bytecode_version() {
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "TEST: java-version overrides bytecode-version"
  setup

  build_jar_with_release 17 "test.jar"

  # bytecode-version=52 (Java 8) would fail, but java-version=17 (bytecode 61) should pass
  if output=$(run_verify "$WORK_DIR" "17" "52" "0"); then
    pass "java-version takes precedence over bytecode-version"
  else
    fail "java-version should override bytecode-version" "output: $output"
  fi

  teardown
}

build_mixed_jar() {
  local jar_name="$1"
  local src_dir="$WORK_DIR/src"
  mkdir -p "$src_dir"
  echo 'public class Good { }' > "$src_dir/Good.java"
  echo 'public class Bad { }' > "$src_dir/Bad.java"
  javac --release 8 -d "$src_dir" "$src_dir/Good.java"
  javac --release 17 -d "$src_dir" "$src_dir/Bad.java"
  jar cf "$WORK_DIR/$jar_name" -C "$src_dir" Good.class -C "$src_dir" Bad.class
  rm -rf "$src_dir"
}

run_verify_with_summary() {
  local summary_file="$WORK_DIR/summary.md"
  INPUT_DIRECTORY="${1}" \
  INPUT_JAVA_VERSION="${2:-}" \
  INPUT_BYTECODE_VERSION="${3:-}" \
  INPUT_MAX_CHECKS="${4:-0}" \
  GITHUB_STEP_SUMMARY="$summary_file" \
  bash "$VERIFY_SH" 2>&1
}

test_all_violations_reported_in_single_jar() {
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "TEST: all violations reported within a single JAR"
  setup

  build_mixed_jar "mixed.jar"

  output=$(run_verify "$WORK_DIR" "" "52" "0" || true)

  if echo "$output" | grep -q "1 violation(s)"; then
    pass "reports violation count"
  else
    fail "should report violation count" "output: $output"
  fi

  if echo "$output" | grep -q "Checked 2 class(es)"; then
    pass "checked all classes before failing"
  else
    fail "should check all classes before failing" "output: $output"
  fi

  teardown
}

test_multiple_jars_all_violations_reported() {
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "TEST: violations in multiple JARs are all reported"
  setup

  build_jar_with_release 17 "bad1.jar"
  build_jar_with_release 17 "bad2.jar"

  output=$(run_verify "$WORK_DIR" "" "52" "0" || true)

  count=$(echo "$output" | grep -c "exceeds allowed" || true)
  if [ "$count" -ge 2 ]; then
    pass "reports violations from both JARs"
  else
    fail "should report violations from both JARs (got $count)" "output: $output"
  fi

  if echo "$output" | grep -q "Bytecode version violations detected"; then
    pass "reports final failure message"
  else
    fail "should report final failure message" "output: $output"
  fi

  teardown
}

test_step_summary_contains_violation_details() {
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "TEST: step summary contains violation details"
  setup

  build_jar_with_release 17 "bad.jar"
  summary_file="$WORK_DIR/summary.md"

  run_verify_with_summary "$WORK_DIR" "" "52" "0" || true

  if [ ! -f "$summary_file" ]; then
    fail "summary file should be created" "file not found: $summary_file"
    teardown
    return
  fi

  summary=$(cat "$summary_file")

  if echo "$summary" | grep -q "### Violations"; then
    pass "summary contains Violations section"
  else
    fail "summary should contain Violations section" "summary: $summary"
  fi

  if echo "$summary" | grep -q "Bytecode Version"; then
    pass "summary contains violation table headers"
  else
    fail "summary should contain violation table headers" "summary: $summary"
  fi

  if echo "$summary" | grep -q "Hello.class"; then
    pass "summary lists the violating class"
  else
    fail "summary should list the violating class" "summary: $summary"
  fi

  teardown
}

test_step_summary_no_violations_section_when_passing() {
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "TEST: step summary has no Violations section when all JARs pass"
  setup

  build_jar_with_release 8 "good.jar"
  summary_file="$WORK_DIR/summary.md"

  run_verify_with_summary "$WORK_DIR" "" "52" "0"

  if [ ! -f "$summary_file" ]; then
    fail "summary file should be created" "file not found: $summary_file"
    teardown
    return
  fi

  summary=$(cat "$summary_file")

  if echo "$summary" | grep -q "### Violations"; then
    fail "summary should NOT contain Violations section" "summary: $summary"
  else
    pass "no Violations section in passing summary"
  fi

  if echo "$summary" | grep -q "✅ Pass"; then
    pass "summary shows pass status"
  else
    fail "summary should show pass status" "summary: $summary"
  fi

  teardown
}

test_step_summary_multiple_jars_detailed() {
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "TEST: step summary shows details for multiple failing JARs"
  setup

  build_jar_with_release 17 "alpha.jar"
  build_jar_multiple_classes 17 "beta.jar"
  build_jar_with_release 8 "good.jar"
  summary_file="$WORK_DIR/summary.md"

  run_verify_with_summary "$WORK_DIR" "" "52" "0" || true

  if [ ! -f "$summary_file" ]; then
    fail "summary file should be created" "file not found: $summary_file"
    teardown
    return
  fi

  summary=$(cat "$summary_file")

  alpha_count=$(echo "$summary" | grep -c "alpha.jar" || true)
  beta_count=$(echo "$summary" | grep -c "beta.jar" || true)
  if [ "$alpha_count" -ge 2 ] && [ "$beta_count" -ge 2 ]; then
    pass "summary contains details for both failing JARs"
  else
    fail "summary should reference both failing JARs in table and details" "summary: $summary"
  fi

  if echo "$summary" | grep -q "✅ Pass"; then
    pass "summary shows passing JAR"
  else
    fail "summary should show passing JAR" "summary: $summary"
  fi

  teardown
}

test_excluded_jar_suffixes_are_skipped() {
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "TEST: javadoc, sources, and test-sources JARs are skipped"
  setup

  build_jar_with_release 8 "lib.jar"
  build_jar_with_release 17 "lib-javadoc.jar"
  build_jar_with_release 17 "lib-sources.jar"
  build_jar_with_release 17 "lib-test-sources.jar"

  if output=$(run_verify "$WORK_DIR" "" "52" "0"); then
    pass "exits with zero (excluded JARs not scanned)"
  else
    fail "should exit with zero — excluded JARs should be skipped" "output: $output"
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
test_java_version_compliant
test_java_version_non_compliant
test_java_version_overrides_bytecode_version
test_all_violations_reported_in_single_jar
test_multiple_jars_all_violations_reported
test_step_summary_contains_violation_details
test_step_summary_no_violations_section_when_passing
test_step_summary_multiple_jars_detailed
test_excluded_jar_suffixes_are_skipped

echo ""
echo "========================================="
echo "Tests run: $TESTS_RUN"
echo "Passed:    $TESTS_PASSED"
echo "Failed:    $TESTS_FAILED"
echo "========================================="

if [ "$TESTS_FAILED" -gt 0 ]; then
  exit 1
fi
