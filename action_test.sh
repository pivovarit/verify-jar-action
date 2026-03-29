#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFY_SH="$SCRIPT_DIR/action.sh"
WORK_DIR=""

set_up() {
  WORK_DIR=$(mktemp -d)
}

tear_down() {
  [ -n "$WORK_DIR" ] && rm -rf "$WORK_DIR"
}

run_verify() {
  INPUT_DIRECTORY="${1}" \
  INPUT_JAVA_VERSION="${2:-}" \
  INPUT_BYTECODE_VERSION="${3:-}" \
  INPUT_MAX_CHECKS="${4:-0}" \
  INPUT_FAIL_ON_VIOLATION="${5:-true}" \
  bash "$VERIFY_SH" 2>&1
}

run_verify_with_summary() {
  local summary_file="$WORK_DIR/summary.md"
  INPUT_DIRECTORY="${1}" \
  INPUT_JAVA_VERSION="${2:-}" \
  INPUT_BYTECODE_VERSION="${3:-}" \
  INPUT_MAX_CHECKS="${4:-0}" \
  INPUT_FAIL_ON_VIOLATION="${5:-true}" \
  GITHUB_STEP_SUMMARY="$summary_file" \
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

# --- Error handling ---

function test_directory_does_not_exist_reports_error() {
  local output
  output=$(run_verify "$WORK_DIR/nonexistent" "" "52" "0" || true)

  assert_contains "does not exist" "$output"
}

function test_directory_does_not_exist_exits_with_non_zero() {
  local exit_code=0
  run_verify "$WORK_DIR/nonexistent" "" "52" "0" > /dev/null 2>&1 || exit_code=$?

  assert_not_equals "0" "$exit_code"
}

function test_no_jar_files_reports_error() {
  local output
  output=$(run_verify "$WORK_DIR" "" "52" "0" || true)

  assert_contains "No .jar files" "$output"
}

function test_no_jar_files_exits_with_non_zero() {
  local exit_code=0
  run_verify "$WORK_DIR" "" "52" "0" > /dev/null 2>&1 || exit_code=$?

  assert_not_equals "0" "$exit_code"
}

# --- Basic compliance ---

function test_compliant_jar_exits_with_zero() {
  build_jar_with_release 8 "good.jar"

  local output
  output=$(run_verify "$WORK_DIR" "" "52" "0")

  assert_contains "Checked" "$output"
}

function test_non_compliant_jar_reports_violation() {
  build_jar_with_release 17 "bad.jar"

  local output
  output=$(run_verify "$WORK_DIR" "" "52" "0" || true)

  assert_contains "exceeds allowed" "$output"
}

function test_non_compliant_jar_exits_with_non_zero() {
  build_jar_with_release 17 "bad.jar"

  local exit_code=0
  run_verify "$WORK_DIR" "" "52" "0" > /dev/null 2>&1 || exit_code=$?

  assert_not_equals "0" "$exit_code"
}

function test_jar_no_class_files_exits_with_zero() {
  build_jar_no_classes "empty.jar"

  local output
  output=$(run_verify "$WORK_DIR" "" "52" "0")

  assert_contains "skipping" "$output"
}

# --- Max checks ---

function test_max_checks_limits_inspection_count() {
  build_jar_multiple_classes 8 "multi.jar"

  local output
  output=$(run_verify "$WORK_DIR" "" "52" "1")
  local checked
  checked=$(echo "$output" | grep -oE 'Checked [0-9]+' | awk '{print $2}')

  assert_equals "1" "$checked"
}

# --- Multiple JARs ---

function test_multiple_jars_mixed_compliance_reports_violation() {
  build_jar_with_release 8 "good.jar"
  build_jar_with_release 17 "bad.jar"

  local output
  output=$(run_verify "$WORK_DIR" "" "52" "0" || true)

  assert_contains "exceeds allowed" "$output"
}

function test_multiple_jars_mixed_compliance_exits_with_non_zero() {
  build_jar_with_release 8 "good.jar"
  build_jar_with_release 17 "bad.jar"

  local exit_code=0
  run_verify "$WORK_DIR" "" "52" "0" > /dev/null 2>&1 || exit_code=$?

  assert_not_equals "0" "$exit_code"
}

# --- Java version input ---

function test_java_version_compliant_jar() {
  build_jar_with_release 8 "good.jar"

  run_verify "$WORK_DIR" "8" "" "0"

  assert_successful_code
}

function test_java_version_non_compliant_jar() {
  build_jar_with_release 17 "bad.jar"

  local output
  output=$(run_verify "$WORK_DIR" "8" "" "0" || true)

  assert_contains "exceeds allowed" "$output"
}

function test_java_version_overrides_bytecode_version() {
  build_jar_with_release 17 "test.jar"

  # bytecode-version=52 (Java 8) would fail, but java-version=17 (bytecode 61) should pass
  run_verify "$WORK_DIR" "17" "52" "0"

  assert_successful_code
}

# --- All violations reported ---

function test_all_violations_reported_in_single_jar() {
  build_mixed_jar "mixed.jar"

  local output
  output=$(run_verify "$WORK_DIR" "" "52" "0" || true)

  assert_contains "1 violation(s)" "$output"
  assert_contains "Checked 2 class(es)" "$output"
}

function test_violations_in_multiple_jars_are_all_reported() {
  build_jar_with_release 17 "bad1.jar"
  build_jar_with_release 17 "bad2.jar"

  local output
  output=$(run_verify "$WORK_DIR" "" "52" "0" || true)
  local count
  count=$(echo "$output" | grep -c "exceeds allowed" || true)

  assert_greater_or_equal_than "2" "$count"
  assert_contains "Bytecode version violations detected" "$output"
}

# --- Step summary ---

function test_step_summary_contains_violation_details() {
  build_jar_with_release 17 "bad.jar"

  run_verify_with_summary "$WORK_DIR" "" "52" "0" || true

  local summary
  summary=$(cat "$WORK_DIR/summary.md")

  assert_contains "### Violations" "$summary"
  assert_contains "Bytecode Version" "$summary"
  assert_contains "Hello.class" "$summary"
}

function test_step_summary_no_violations_section_when_passing() {
  build_jar_with_release 8 "good.jar"

  run_verify_with_summary "$WORK_DIR" "" "52" "0"

  local summary
  summary=$(cat "$WORK_DIR/summary.md")

  assert_not_contains "### Violations" "$summary"
  assert_contains "Pass" "$summary"
}

function test_step_summary_multiple_jars_detailed() {
  build_jar_with_release 17 "alpha.jar"
  build_jar_multiple_classes 17 "beta.jar"
  build_jar_with_release 8 "good.jar"

  run_verify_with_summary "$WORK_DIR" "" "52" "0" || true

  local summary
  summary=$(cat "$WORK_DIR/summary.md")
  local alpha_count beta_count
  alpha_count=$(echo "$summary" | grep -c "alpha.jar" || true)
  beta_count=$(echo "$summary" | grep -c "beta.jar" || true)

  assert_greater_or_equal_than "2" "$alpha_count"
  assert_greater_or_equal_than "2" "$beta_count"
  assert_contains "Pass" "$summary"
}

# --- Excluded JAR suffixes ---

function test_excluded_jar_suffixes_are_skipped() {
  build_jar_with_release 8 "lib.jar"
  build_jar_with_release 17 "lib-javadoc.jar"
  build_jar_with_release 17 "lib-sources.jar"
  build_jar_with_release 17 "lib-test-sources.jar"

  run_verify "$WORK_DIR" "" "52" "0"

  assert_successful_code
}

# --- Report-only mode ---

function test_report_only_mode_exits_with_zero() {
  build_jar_with_release 17 "bad.jar"

  local output
  output=$(run_verify "$WORK_DIR" "" "52" "0" "false")

  assert_contains "report-only mode" "$output"
}

function test_report_only_mode_shows_warnings() {
  build_jar_with_release 17 "bad.jar"

  local output
  output=$(run_verify "$WORK_DIR" "" "52" "0" "false")

  assert_contains "WARNING:" "$output"
  assert_contains "warning(s)" "$output"
}

function test_report_only_mode_summary_shows_warn() {
  build_jar_with_release 17 "bad.jar"

  run_verify_with_summary "$WORK_DIR" "" "52" "0" "false"

  local summary
  summary=$(cat "$WORK_DIR/summary.md")

  assert_contains "Warn" "$summary"
  assert_contains "### Violations" "$summary"
}

function test_fail_on_violation_true_still_fails() {
  build_jar_with_release 17 "bad.jar"

  local exit_code=0
  run_verify "$WORK_DIR" "" "52" "0" "true" > /dev/null 2>&1 || exit_code=$?

  assert_not_equals "0" "$exit_code"
}

function test_report_only_no_violations_passes_cleanly() {
  build_jar_with_release 8 "good.jar"

  local output
  output=$(run_verify "$WORK_DIR" "" "52" "0" "false")

  assert_not_contains "report-only mode" "$output"
}
