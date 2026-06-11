# ADR-002: JSON as internal interchange format

**Status:** Accepted  
**Date:** 2026-05-25

## Context

Spec files can be authored in YAML, TOML, or JSON. The Kujo validation, rendering, and export modules need a consistent input format. We needed to decide on a single internal representation.

## Decision

All spec files are converted to JSON before being processed by Kujo modules. The `spec_to_json()` function in `scripts/spec` handles the conversion.

## Rationale

- **Kujo-native:** Kujo has built-in `parse_json()` and `to_json()` functions. JSON is the only structured data format Kujo can natively read and write.
- **Deterministic:** JSON has a single canonical representation. No parsing ambiguities between YAML/TOML dialects.
- **Simple contract:** Kujo modules receive a single JSON file path via `--json <path>`. No need to handle multiple formats in Kujo code.
- **Cache-friendly:** JSON files are easy to cache (mtime-based) and diff.

## Consequences

- **Positive:** Kujo modules are format-agnostic — they never need to know whether the original was YAML, TOML, or JSON.
- **Positive:** The `spec_helpers.py` helper script can operate on JSON without needing YAML/TOML libraries.
- **Negative:** An extra conversion step is needed for every operation on YAML/TOML specs.
- **Mitigation:** mtime-based JSON caching (`PERF-02`) makes repeated operations on unchanged specs near-instant.

## Alternatives Considered

- **Pass raw spec content to Kujo modules:** Rejected because Kujo has no YAML/TOML parser and embedding one in every module would duplicate effort.
- **Use a binary format (MessagePack, CBOR):** Rejected as overengineered. JSON is human-readable, debuggable, and sufficient for spec-sized documents.
