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

- `directory` — directory to scan for JARs (default: `target`)
- `java-version` — maximum allowed Java version (e.g. `8`, `11`, `17`, `21`). Takes precedence over `bytecode-version` if both are provided.
- `bytecode-version` — maximum allowed class file bytecode version (e.g. `52` = Java 8, `55` = Java 11, `61` = Java 17). Ignored if `java-version` is provided. (default: `52`)
- `max-checks` — maximum number of `.class` files to check per JAR (default: `0`, no limit)

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

      - name: Verify jar compatibility (using java-version)
        uses: pivovarit/verify-jar-action@v1.2.0
        with:
          directory: 'target'
          java-version: '11'

      - name: Verify jar compatibility (using bytecode-version)
        uses: pivovarit/verify-jar-action@v1.2.0
        with:
          directory: 'target'
          bytecode-version: '52'
          max-checks: 10
