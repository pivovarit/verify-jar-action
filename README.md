# verify-jar-action

Fail the build if any `.class` file in a JAR is compiled for a higher Java version than allowed.

---

## Features

- Scans JAR files in a given directory.
- Inspects all `.class` files (ignores `module-info.class` and `package-info.class`).
- Checks the major bytecode version of each class.
- Fails the workflow if any class exceeds the configured maximum Java version.

---

## Inputs

- `directory`
- `bytecode-version`
- `max-checks`

---

## Usage

```yaml
name: CI
on: [push, pull_request]

jobs:
  verify-jar:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5

      - name: Verify jar compatibility
        uses: pivovarit/verify-jar-action@v1
        with:
          directory: 'target'
          bytecode-version: '52'
          max-checks: 10
