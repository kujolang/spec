# Project Directory Structure

Recommended layouts for organizing spec files in your projects.

## Standard Layout

```
my-project/
├── specs/                    # All spec files live here
│   ├── features/             # Feature specs
│   │   ├── auth.spec.yml
│   │   ├── dark-mode.spec.yml
│   │   └── search.spec.yml
│   ├── bugs/                 # Bug fix specs
│   │   ├── fix-123.spec.yml
│   │   └── fix-456.spec.yml
│   ├── chores/               # Maintenance/refactor specs
│   │   └── upgrade-deps.spec.yml
│   └── templates/            # Spec templates for `spec init --from template:`
│       ├── feature.template.yml
│       └── bugfix.template.yml
├── src/                      # Your application code
├── tests/                    # Your tests
├── README.md
└── kennel.toml
```

## Flat Layout (small projects)

For projects with fewer than 20 specs, a flat structure works:

```
my-project/
├── specs/
│   ├── add-login.spec.yml
│   ├── fix-crash.spec.yml
│   └── api-v2.spec.yml
└── ...
```

## Hidden Specs Layout

Prefers `.specs/` (hidden directory) to keep the root clean:

```
my-project/
├── .specs/
│   ├── features/
│   │   └── auth.spec.yml
│   └── ...
└── ...
```

## Monorepo Layout

For monorepos, colocate specs with the package they describe:

```
monorepo/
├── packages/
│   ├── web/
│   │   ├── specs/
│   │   │   └── dashboard.spec.yml
│   │   └── src/
│   ├── api/
│   │   ├── specs/
│   │   │   └── rate-limiting.spec.yml
│   │   └── src/
│   └── shared/
│       ├── specs/
│       │   └── design-system.spec.yml
│       └── src/
└── ...
```

## File Naming Convention

Spec files use the double extension pattern: `.spec.yml`, `.spec.yaml`, `.spec.toml`, or `.spec.json`.

Recommended naming:
- `descriptive-kebab-case.spec.yml` for features
- `fix-<issue-number>.spec.yml` for bug fixes
- `YYYY-MM-brief-description.spec.yml` for dated specs

The `spec list` command discovers files matching these patterns:
- `*.spec.yml`
- `*.spec.yaml`
- `*.spec.toml`
- `*.spec.json`

## Discovery Depth

`spec list` scans up to 3 levels deep by default. For deeper hierarchies, use `--max-depth`:

```bash
spec list --max-depth 5
```

## CI Integration

In CI, keep specs alongside the code they gate:

```yaml
# .github/workflows/spec-check.yml
- name: Validate specs
  run: spec validate-all ./specs --quiet
```

## Templates

Store reusable templates in a `templates/` subdirectory:

```
specs/
└── templates/
    ├── feature.template.yml
    ├── bugfix.template.yml
    └── refactor.template.yml
```

Use them with `spec init --from template:feature`.
