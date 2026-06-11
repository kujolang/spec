# ADR-005: Cross-module imports via src/common.kujo

**Status:** Accepted  
**Date:** 2026-05-25

## Context

The three Kujo modules (`validate.kujo`, `render.kujo`, `export.kujo`) each needed `dict_get` and `dict_get_arr` helper functions. Initially, these were duplicated inline in each module (24 lines × 3 = 72 lines of duplicated code).

Kujo v1.0.0 had a known limitation: `from X import Y` did not work for standalone scripts run via `kujo run src/module.kujo`. Imports only resolved in `--interpreter` mode with a `main.kujo` entry point.

## Decision

Initially: duplicate the helpers inline (DRY-01 blocked).  
After Kujo runtime fix (May 2026): consolidate into `src/common.kujo` and use `from src.common import dict_get, dict_get_arr, parse_json_arg, parse_format_arg`.

## Rationale

- **DRY principle:** 66 lines of duplicated code eliminated across 3 modules.
- **Single source of truth:** Bug fixes to `dict_get` or `dict_get_arr` now happen in one place.
- **Kennel ecosystem:** `src/common.kujo` can be exported as a kennel package for other Kujo projects to import.
- **Kujo showcase:** Demonstrates Kujo's cross-module import capability, which is essential for building larger Kujo codebases.

## Consequences

- **Positive:** Code is more maintainable and the codebase is smaller.
- **Positive:** `parse_json_arg` and `parse_format_arg` shared parsers eliminate duplicated arg-parsing loops in `main()` functions.
- **Negative:** Adds a dependency edge from each module to `common.kujo`. All three modules must be kept compatible with `common.kujo`'s function signatures.
- **Mitigation:** `common.kujo` functions have stable, documented signatures. Breaking changes are caught by the test suite.

## Alternatives Considered

- **Keep inline duplication:** Rejected once the Kujo runtime supported cross-module imports. The maintenance burden of keeping three copies in sync was already causing drift (validate.kujo used `default_val` parameter name while render/export used `dflt`).
- **Use a preprocessor to inline imports:** Rejected as overengineered. The Kujo runtime fix made it unnecessary.
