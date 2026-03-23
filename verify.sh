#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

DIR="${INPUT_DIRECTORY}"
MAX_CHECKS="${INPUT_MAX_CHECKS}"

if [ -n "${INPUT_JAVA_VERSION:-}" ]; then
  BYTECODE_VERSION=$(( INPUT_JAVA_VERSION + 44 ))
else
  BYTECODE_VERSION="${INPUT_BYTECODE_VERSION}"
fi

echo -e "${BLUE}Scanning JARs in: $DIR${NC}"

if [ ! -d "$DIR" ]; then
  echo -e "${RED}ERROR: Directory does not exist: $DIR${NC}"
  exit 1
fi

mapfile -d '' JARS < <(find "$DIR" -type f -name "*.jar" ! -name "*-javadoc.jar" ! -name "*-sources.jar" ! -name "*-test-sources.jar" -print0)

if [ "${#JARS[@]}" -eq 0 ]; then
  echo -e "${RED}ERROR: No .jar files found in $DIR${NC}"
  exit 1
fi

echo -e "${GREEN}Found ${#JARS[@]} JAR(s)${NC}"

SUMMARY_ROWS=""
FAILURE_DETAILS=""
HAS_FAILURES=0

write_summary() {
  [ -n "${GITHUB_STEP_SUMMARY:-}" ] || return 0
  [ -n "$SUMMARY_ROWS" ] || return 0
  {
    echo "## JAR Version Check"
    echo ""
    echo "Allowed: bytecode \`$BYTECODE_VERSION\`"
    echo ""
    echo "| JAR | Classes Checked | Result |"
    echo "| --- | --- | --- |"
    printf "%b" "$SUMMARY_ROWS"
    if [ -n "$FAILURE_DETAILS" ]; then
      echo ""
      echo "### Violations"
      echo ""
      printf "%b" "$FAILURE_DETAILS"
    fi
  } >> "$GITHUB_STEP_SUMMARY"
}

trap write_summary EXIT

for JAR_FILE in "${JARS[@]}"; do
  echo ""
  echo -e "${BLUE}Checking $JAR_FILE${NC}"

  classes=$(jar tf "$JAR_FILE" | grep '\.class$' | grep -vE 'module-info|package-info' || true)

  if [ -z "$classes" ]; then
    echo -e "  ${YELLOW}(no class files, skipping)${NC}"
    SUMMARY_ROWS+="| \`$(basename "$JAR_FILE")\` | 0 | ⚠️ No classes |\n"
    continue
  fi

  class_list="$classes"
  if [ "$MAX_CHECKS" -gt 0 ]; then
    class_list=$(echo "$classes" | head -n "$MAX_CHECKS")
  fi

  JAR_CHECKED=0
  JAR_FAILED=0
  JAR_VIOLATIONS=""

  while read -r f; do
    if ! bytes=$(unzip -p "$JAR_FILE" "$f" 2>/dev/null | od -An -N8 -tu1); then
      echo -e "  ${YELLOW}$f ${CYAN}->${YELLOW} skipped (could not read class)${NC}"
      continue
    fi

    major=$(awk 'NF>=8 {print $7 * 256 + $8}' <<< "$bytes")

    if [ -z "$major" ]; then
      echo -e "  ${YELLOW}$f ${CYAN}->${YELLOW} skipped (no major version found)${NC}"
      continue
    fi

    JAR_CHECKED=$((JAR_CHECKED + 1))

    if [ "$major" -gt "$BYTECODE_VERSION" ]; then
      echo -e "  ${RED}ERROR: $f — bytecode $major exceeds allowed $BYTECODE_VERSION${NC}"
      JAR_FAILED=$((JAR_FAILED + 1))
      JAR_VIOLATIONS+="| \`$f\` | $major | $BYTECODE_VERSION |\n"
    fi
  done < <(echo "$class_list")

  if [ "$JAR_FAILED" -gt 0 ]; then
    HAS_FAILURES=1
    echo -e "  ${RED}Checked $JAR_CHECKED class(es) — $JAR_FAILED violation(s)${NC}"
    SUMMARY_ROWS+="| \`$(basename "$JAR_FILE")\` | $JAR_CHECKED | ❌ Fail ($JAR_FAILED violation(s)) |\n"
    FAILURE_DETAILS+="<details>\n<summary><code>$(basename "$JAR_FILE")</code> — $JAR_FAILED violation(s)</summary>\n\n"
    FAILURE_DETAILS+="| Class | Bytecode Version | Allowed |\n"
    FAILURE_DETAILS+="| --- | --- | --- |\n"
    FAILURE_DETAILS+="$JAR_VIOLATIONS"
    FAILURE_DETAILS+="\n</details>\n\n"
  else
    echo -e "  ${GREEN}Checked $JAR_CHECKED class(es) — OK${NC}"
    SUMMARY_ROWS+="| \`$(basename "$JAR_FILE")\` | $JAR_CHECKED | ✅ Pass |\n"
  fi
done

if [ "$HAS_FAILURES" -eq 1 ]; then
  echo ""
  echo -e "${RED}Bytecode version violations detected${NC}"
  exit 1
fi
