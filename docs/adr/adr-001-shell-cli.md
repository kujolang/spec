# ADR-001: Shell script CLI instead of pure Kujo

**Status:** Accepted  
**Date:** 2026-05-25

## Context

The Spec tool needed a command-line interface. Two options were considered:
1. Write the CLI entirely in Kujo, using Kujo's native file I/O, arg parsing, and subprocess calls
2. Write the CLI in bash, using Kujo modules for the core logic (validate, render, export)

## Decision

Use a bash shell script as the CLI wrapper (`scripts/spec`), with Kujo modules handling the domain logic.

## Rationale

- **Multi-format parsing:** The shell wrapper delegates structured-data conversion to Kujo's native parsers and keeps filesystem/process orchestration in Bash and Python helpers.
- **Kujo runtime maturity:** At v1.0.0, Kujo's `kujo run` mode for standalone scripts works well for the core logic modules but lacks some conveniences for CLI building (arg parsing libraries, colored output, etc.).
- **Unix philosophy:** The shell script follows Unix conventions — it's a thin orchestrator that delegates to specialized tools.
- **Developer familiarity:** Bash is universally available on macOS and Linux. No additional runtime is needed beyond Python 3 and the Kujo binary.

## Consequences

- **Positive:** Quick development of CLI features (14 commands in under 1,000 lines of bash)
- **Positive:** Easy to install — single script, no compilation
- **Negative:** Cross-platform edge cases between macOS and Linux (stat flags, sed syntax, timeout availability)
- **Negative:** Performance overhead from Python subprocess calls (mitigated by `spec_helpers.py` and caching in v0.1.0+)
- **Mitigation:** Created `spec_helpers.py` to reduce Python startup overhead. The Kujo runtime is used for core operations where it excels.

## Alternatives Considered

- **Pure Kujo CLI:** Rejected because filesystem/process orchestration and cross-platform CLI ergonomics still benefit from the wrapper. Structured-data parsing has since moved to Kujo-native functions.
- **Python CLI:** Rejected because the project's purpose is to showcase the Kujo language. A Python CLI would defeat that purpose.
