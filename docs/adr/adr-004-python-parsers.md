# ADR-004: Python for YAML/TOML parsing

**Status:** Accepted  
**Date:** 2026-05-25

## Context

Spec needs to parse YAML and TOML files into JSON before Kujo modules can process them. Two approaches were considered:
1. Use Python's `yaml` and `tomllib`/`tomli` libraries
2. Write Kujo-native parsers for the YAML and TOML subsets that Spec uses

## Decision

Use Python 3 with `yaml.safe_load` (PyYAML) for YAML and a simple Python script for TOML.

## Rationale

- **Maturity:** PyYAML is battle-tested and handles edge cases correctly.
- **Safety:** `yaml.safe_load` prevents arbitrary code execution (unlike `yaml.load`).
- **Speed of development:** Python parsers took hours to integrate. Kujo-native parsers would take days or weeks to reach the same level of correctness.
- **Subset usage:** Spec only uses a small subset of YAML/TOML (flat key-value, arrays, no anchors/tags/complex nesting). This means the Python scripts are simple and fast.

## Consequences

- **Positive:** Reliable parsing with well-tested libraries.
- **Positive:** Clear error messages from Python tracebacks when parsing fails.
- **Negative:** Python 3 is a hard dependency for YAML/TOML spec users. JSON-only users don't need Python.
- **Negative:** Python subprocess startup overhead (~50ms per call). Mitigated by `spec_helpers.py` batch operations and JSON caching.
- **Future:** Kujo-native YAML/TOML parsers are on the roadmap (SHOW-02, SHOW-03) to eventually remove the Python dependency.

## Alternatives Considered

- **Use a different scripting language (Node.js, Ruby, Perl):** Rejected because Python 3 is nearly as universal as bash and has the best YAML/TOML library support.
- **Bundle a YAML parser binary:** Rejected because it adds a platform-specific binary dependency and complicates installation.
