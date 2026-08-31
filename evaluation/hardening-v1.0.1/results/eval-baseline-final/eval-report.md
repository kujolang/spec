# Eval Report: Spec v1.0.1 hardening outcome evaluation

## Summary

| Metric | Value |
|--------|-------|
| Suite | Spec v1.0.1 hardening outcome evaluation |
| Version | 0.0.0 |
| Total Tests | 11 |
| Passed | 3 |
| Failed | 8 |
| Duration | 100503ms |
| Parallel Requested | false |
| Parallel Used | false |
| Parallel Mode | serial |
| Parallel Workers | 1 |
| Pass Rate | 0% |

### Result: ❌ 8 FAILED

## Test Results

| # | Status | Test | Check | Message |
|---|--------|------|-------|---------|
| 1 | ✅ | minimal version contract | command_succeeds | Command succeeded (exit 0) |
| 2 | ❌ | typical full-schema validation | command_succeeds | Command failed with exit code 1 |
| 3 | ✅ | large 100-file batch | command_succeeds | Command succeeded (exit 0) |
| 4 | ❌ | stress 256-failure exit status | command_succeeds | Command failed with exit code 1 |
| 5 | ❌ | runtime failure fails closed | command_succeeds | Command failed with exit code 1 |
| 6 | ✅ | agent context remains useful and bounded | command_succeeds | Command succeeded (exit 0) |
| 7 | ❌ | interactive YAML injection rejected | command_succeeds | Command failed with exit code 1 |
| 8 | ❌ | graph labels are escaped | command_succeeds | Command failed with exit code 1 |
| 9 | ❌ | requested initialization format honored | command_succeeds | Command failed with exit code 1 |
| 10 | ❌ | cache symlink not followed | command_succeeds | Command failed with exit code 1 |
| 11 | ❌ | invalid timeout rejected early | command_succeeds | Command failed with exit code 1 |

## Failed Test Details

### typical full-schema validation

- **Check**: `command_succeeds`
- **Message**: Command failed with exit code 1
- **allowed_command_patterns**: []
- **allowed_commands**: []
- **blocked_arg_patterns**: []
- **command**: python3 "$SPEC_ROOT/checks/hardening-v1.0.1/cases.py" --target "$SPEC_TARGET_ROOT" --case full_schema_validation
- **command_pattern_match_mode**: substring
- **exit_code**: 1
- **stderr**: 
- **stdout**: {"case": "full_schema_validation", "exit_code": 1, "passed": false, "stderr_bytes": 0, "stderr_preview": "", "stdout_bytes": 202, "stdout_preview": "{\"errors\": [], \"valid\": false, \"warnings\": [\"Unknown top-level field: updated_at\", \"Unknown top-level field: estimated_hours\", \"Unknown top-level field: children\", \"Unknown top-level field: metadata\"]}\n"}


### stress 256-failure exit status

- **Check**: `command_succeeds`
- **Message**: Command failed with exit code 1
- **allowed_command_patterns**: []
- **allowed_commands**: []
- **blocked_arg_patterns**: []
- **command**: python3 "$SPEC_ROOT/checks/hardening-v1.0.1/cases.py" --target "$SPEC_TARGET_ROOT" --case failure_count_256
- **command_pattern_match_mode**: substring
- **exit_code**: 1
- **stderr**: 
- **stdout**: {"case": "failure_count_256", "exit_code": 0, "passed": false, "stderr_bytes": 0, "stderr_preview": "", "stdout_bytes": 48, "stdout_preview": "validate --all: 0 passed, 256 failed, 256 total\n"}


### runtime failure fails closed

- **Check**: `command_succeeds`
- **Message**: Command failed with exit code 1
- **allowed_command_patterns**: []
- **allowed_commands**: []
- **blocked_arg_patterns**: []
- **command**: python3 "$SPEC_ROOT/checks/hardening-v1.0.1/cases.py" --target "$SPEC_TARGET_ROOT" --case runtime_failure
- **command_pattern_match_mode**: substring
- **exit_code**: 1
- **stderr**: 
- **stdout**: {"case": "runtime_failure", "exit_code": 0, "passed": false, "stderr_bytes": 0, "stderr_preview": "", "stdout_bytes": 1, "stdout_preview": "\n"}


### interactive YAML injection rejected

- **Check**: `command_succeeds`
- **Message**: Command failed with exit code 1
- **allowed_command_patterns**: []
- **allowed_commands**: []
- **blocked_arg_patterns**: []
- **command**: python3 "$SPEC_ROOT/checks/hardening-v1.0.1/cases.py" --target "$SPEC_TARGET_ROOT" --case interactive_injection
- **command_pattern_match_mode**: substring
- **exit_code**: 1
- **stderr**: 
- **stdout**: {"case": "interactive_injection", "exit_code": 0, "passed": false, "stderr_bytes": 0, "stderr_preview": "", "stdout_bytes": 228, "stdout_preview": "=== Spec Interactive Creator ===\nPress Enter to accept defaults.\n\nName: Goal: Priority [medium]: Tags (comma-separated): Output file [spec.yml]: \nCreated: interactive.spec.yml\nRun 'spec validate interactive.spec.yml' to verify.\n"}


### graph labels are escaped

- **Check**: `command_succeeds`
- **Message**: Command failed with exit code 1
- **allowed_command_patterns**: []
- **allowed_commands**: []
- **blocked_arg_patterns**: []
- **command**: python3 "$SPEC_ROOT/checks/hardening-v1.0.1/cases.py" --target "$SPEC_TARGET_ROOT" --case graph_escaping
- **command_pattern_match_mode**: substring
- **exit_code**: 1
- **stderr**: 
- **stdout**: {"case": "graph_escaping", "exit_code": 0, "passed": false, "stderr_bytes": 0, "stderr_preview": "", "stdout_bytes": 63, "stdout_preview": "```mermaid\ngraph TD\n    spec0[\"safe\"]\n    injected[\"node\"]\n```\n"}


### requested initialization format honored

- **Check**: `command_succeeds`
- **Message**: Command failed with exit code 1
- **allowed_command_patterns**: []
- **allowed_commands**: []
- **blocked_arg_patterns**: []
- **command**: python3 "$SPEC_ROOT/checks/hardening-v1.0.1/cases.py" --target "$SPEC_TARGET_ROOT" --case requested_format
- **command_pattern_match_mode**: substring
- **exit_code**: 1
- **stderr**: 
- **stdout**: {"case": "requested_format", "exit_code": 0, "passed": false, "stderr_bytes": 0, "stderr_preview": "", "stdout_bytes": 54, "stdout_preview": "Created (from template:evaluation): created.spec.json\n"}


### cache symlink not followed

- **Check**: `command_succeeds`
- **Message**: Command failed with exit code 1
- **allowed_command_patterns**: []
- **allowed_commands**: []
- **blocked_arg_patterns**: []
- **command**: python3 "$SPEC_ROOT/checks/hardening-v1.0.1/cases.py" --target "$SPEC_TARGET_ROOT" --case cache_symlink
- **command_pattern_match_mode**: substring
- **exit_code**: 1
- **stderr**: 
- **stdout**: {"case": "cache_symlink", "exit_code": 0, "passed": false, "stderr_bytes": 0, "stderr_preview": "", "stdout_bytes": 53, "stdout_preview": "Validating: cache-input.spec.yml\nPASS: Spec is valid\n"}


### invalid timeout rejected early

- **Check**: `command_succeeds`
- **Message**: Command failed with exit code 1
- **allowed_command_patterns**: []
- **allowed_commands**: []
- **blocked_arg_patterns**: []
- **command**: python3 "$SPEC_ROOT/checks/hardening-v1.0.1/cases.py" --target "$SPEC_TARGET_ROOT" --case timeout_validation
- **command_pattern_match_mode**: substring
- **exit_code**: 1
- **stderr**: 
- **stdout**: {"case": "timeout_validation", "exit_code": 0, "passed": false, "stderr_bytes": 0, "stderr_preview": "", "stdout_bytes": 69, "stdout_preview": "{\"version\": \"1.0.0\", \"contract\": \"1.0.0\", \"schema_version\": \"1.0.0\"}\n"}


---
*Report generated by Eval*
