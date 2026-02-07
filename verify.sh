#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

DIR="${INPUT_DIRECTORY}"
BYTECODE_VERSION="${INPUT_BYTECODE_VERSION}"
MAX_CHECKS="${INPUT_MAX_CHECKS}"

echo -e "${BLUE}Scanning JARs in: $DIR${NC}"

if [ ! -d "$DIR" ]; then
  echo -e "${RED}ERROR: Directory does not exist: $DIR${NC}"
  exit 1
fi

mapfile -d '' JARS < <(find "$DIR" -type f -name "*.jar" -print0)

if [ "${#JARS[@]}" -eq 0 ]; then
  echo -e "${RED}ERROR: No .jar files found in $DIR${NC}"
  exit 1
fi

echo -e "${GREEN}Found ${#JARS[@]} JAR(s)${NC}"

for JAR_FILE in "${JARS[@]}"; do
  echo ""
  echo -e "${BLUE}Checking $JAR_FILE${NC}"

  classes=$(jar tf "$JAR_FILE" | grep '\.class$' | grep -vE 'module-info|package-info' || true)

  if [ -z "$classes" ]; then
    echo -e "  ${YELLOW}(no class files, skipping)${NC}"
    continue
  fi

  class_list="$classes"
  if [ "$MAX_CHECKS" -gt 0 ]; then
    class_list=$(echo "$classes" | head -n "$MAX_CHECKS")
  fi

  echo "$class_list" | while read -r f; do
    class_name="${f%.class}"
    class_name="${class_name//\//.}"

    if ! out=$(javap -verbose -cp "$JAR_FILE" "$class_name" 2>/dev/null); then
      echo -e "  ${YELLOW}$f ${CYAN}->${YELLOW} skipped (javap could not read class)${NC}"
      continue
    fi

    major=$(awk '/major version/ {print $3}' <<< "$out")

    if [ -z "$major" ]; then
      echo -e "  ${YELLOW}$f ${CYAN}->${YELLOW} skipped (no major version found)${NC}"
      continue
    fi

    echo -e "  $f ${CYAN}->${YELLOW} major version ${GREEN}$major${NC}"

    if [ "$major" -gt "$BYTECODE_VERSION" ]; then
      echo -e "${RED}ERROR: $f in $JAR_FILE is $major, exceeds allowed $BYTECODE_VERSION${NC}"
      exit 1
    fi
  done
done
