# ADR-003: YAML as recommended spec format

**Status:** Accepted  
**Date:** 2026-05-25

## Context

Spec supports three formats: YAML, TOML, and JSON. We needed to recommend one as the primary format for documentation, examples, and templates.

## Decision

YAML (`.spec.yml`) is the recommended format for authoring specs.

## Rationale

- **Human readability:** YAML's minimal syntax (no braces, no quotes for simple strings) makes specs easier to read and write than JSON or TOML.
- **Comment support:** YAML supports `# comments`, which are essential for documenting why decisions were made within a spec file. JSON does not support comments.
- **Industry standard:** YAML is the dominant configuration format in DevOps (Docker Compose, Kubernetes, Ansible, GitHub Actions). Developers are already familiar with it.
- **Multi-line strings:** YAML's `|` and `>` block scalars make long goal descriptions and background sections readable without embedded `\n` characters.

## Consequences

- **Positive:** Examples and templates use YAML, providing a consistent look.
- **Positive:** Comments in spec files survive round-trip conversion (YAML → JSON → YAML preserves content, though comments are lost).
- **Negative:** YAML has sharp edges (the Norway problem, accidental float parsing). Mitigated by using `yaml.safe_load` and documenting the supported YAML subset.
- **Negative:** Not all developers prefer YAML. JSON and TOML remain fully supported alternatives.

## Alternatives Considered

- **TOML as primary:** Rejected because TOML lacks multi-line string support suitable for long goal/background sections and has no comment convention for inline documentation.
- **JSON as primary:** Rejected because JSON lacks comments and requires quoting all keys and strings, making hand-authored specs noisy.
