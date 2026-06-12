# Spec Cookbook

Real-world usage patterns and examples for Spec.

## Using Spec in CI to Gate PRs

```bash
# .github/workflows/spec-check.yml
- name: Validate all specs
  run: spec validate-all . --quiet
```

## Generating Project Documentation from Specs

```bash
# Render all specs to a docs directory
mkdir -p docs/specs/
spec list --json . | python3 -c "import json,sys; [print(d['file']) for d in json.load(sys.stdin)]" | while IFS= read -r f; do
  spec render "$f" --output "docs/specs/$(basename "$f" .yml).md"
done
```

## Using Specs as Agent Context for Automated PRs

```bash
# Export spec as agent context, feed to an AI coding agent
spec export-agent-context feature.spec.yml --output /tmp/agent-context.txt
# The agent reads this context and implements the spec
```

## Spec-Driven Development Workflow

```bash
# 1. Create a spec for the feature
spec init --name "add-dark-mode" --output specs/dark-mode.spec.yml

# 2. Fill in the spec (goal, scope, acceptance criteria, etc.)
vim specs/dark-mode.spec.yml

# 3. Validate the spec
spec validate specs/dark-mode.spec.yml

# 4. Set status to ready
spec status specs/dark-mode.spec.yml --set ready

# 5. Export as agent context for implementation
spec export-agent-context specs/dark-mode.spec.yml

# 6. After implementation, set to completed
spec status specs/dark-mode.spec.yml --set completed
```

## Integrating Spec with GitHub Issues

```bash
# Create a spec from a GitHub issue (requires gh CLI)
spec init --from github:OWNER/REPO/123 --output specs/issue-123.spec.yml
spec validate specs/issue-123.spec.yml
```

## Batch Validation in Pre-commit Hook

```bash
# .git/hooks/pre-commit
#!/bin/bash
changed_specs=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.spec\.(yml|yaml|toml|json)$' || true)
if [ -n "$changed_specs" ]; then
  echo "$changed_specs" | while IFS= read -r f; do
    spec validate "$f" --quiet || exit 1
  done
fi
```

## Searching and Filtering

```bash
# Find all high-priority specs
spec search --priority high

# Find specs tagged "security"
spec search --tag security

# Full-text search
spec search --query "authentication"
```

## Converting Formats

```bash
# Convert YAML spec to JSON for machine processing
spec convert spec.yml --to json --output spec.json

# Convert JSON to TOML
spec convert spec.json --to toml --output spec.toml
```

## Comparing Spec Versions

```bash
# See what changed between versions
spec diff spec-v1.yml spec-v2.yml
```

## Exporting for kujo-eval

```bash
# Export eval requirements as an eval suite
spec export-eval spec.yml --output eval_suite.json

# Run the eval suite (if kujo-eval is installed)
eval run eval_suite.json
```

## Watching for Changes

```bash
# Auto-re-validate on every save
spec watch spec.yml

# Auto-re-render to Markdown on every save
spec watch spec.yml render
```
