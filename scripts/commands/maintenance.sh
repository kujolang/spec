#!/usr/bin/env bash
# Command handlers extracted from scripts/spec for maintainability.
# This file is sourced by scripts/spec and relies on shared globals/functions.

spec_cmd_ci() {
	local dir="." strict=false format="text" max_files=0 fail_fast=false jobs=1
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--strict) strict=true; shift ;;
			--format)
				[[ $# -ge 2 ]] || die "Usage: spec ci [<directory>] [--strict] [--format text|json|github] [--max-files <n>] [--fail-fast] [--jobs <n>]"
				format="$2"
				shift 2
				;;
			--max-files)
				[[ $# -ge 2 ]] || die "--max-files requires a positive integer"
				max_files="$2"
				shift 2
				;;
			--fail-fast) fail_fast=true; shift ;;
			--jobs)
				[[ $# -ge 2 ]] || die "--jobs requires a positive integer"
				jobs="$2"
				shift 2
				;;
			--help|-h)
				echo "Usage: spec ci [<directory>] [--strict] [--format text|json|github] [--max-files <n>] [--fail-fast] [--jobs <n>]"
				return 0
				;;
			--*) die "Unknown option: $1" ;;
			*)
				if [[ "$dir" == "." ]]; then
					dir="$1"
					shift
				else
					die "Unexpected argument: $1"
				fi
				;;
		esac
	done

	[[ "$format" =~ ^(text|json|github)$ ]] || die "Invalid format: $format (use text, json, or github)"
	[[ "$max_files" =~ ^[0-9]+$ ]] || die "--max-files must be a positive integer"
	[[ "$jobs" =~ ^[0-9]+$ ]] || die "--jobs must be a positive integer"
	[[ "$jobs" -ge 1 ]] || die "--jobs must be at least 1"

	[[ -d "$dir" ]] || die "Directory not found: $dir"
	local files; files="$(find "$dir" -maxdepth 5 -type f \( -name '*.spec.yml' -o -name '*.spec.yaml' -o -name '*.spec.toml' -o -name '*.spec.json' \) 2>/dev/null | sort)" || true
	[[ -z "$files" ]] && die "No spec files found in $dir"

	local total=0 passed=0 failed=0 truncated=false truncated_reason=""
	local failures=()
	local scan_files=()

	while IFS= read -r f; do
		[[ -z "$f" ]] && continue
		if [[ "$max_files" -gt 0 ]] && [[ "${#scan_files[@]}" -ge "$max_files" ]]; then
			truncated=true
			truncated_reason="max-files"
			break
		fi
		scan_files+=("$f")
	done <<< "$files"

	if [[ "${#scan_files[@]}" -eq 0 ]]; then
		die "No spec files selected for validation"
	fi

	if [[ "$jobs" -eq 1 ]] || [[ "${#scan_files[@]}" -eq 1 ]]; then
		local f
		for f in "${scan_files[@]}"; do
			total=$((total + 1))
			if validate_file_quiet "$f" "$strict"; then
				passed=$((passed + 1))
			else
				failed=$((failed + 1))
				failures+=("$f")
				if $fail_fast; then
					[[ "$total" -lt "${#scan_files[@]}" ]] && truncated=true
					[[ "$total" -lt "${#scan_files[@]}" ]] && truncated_reason="fail-fast"
					break
				fi
			fi
		done
	else
		# Parallel path keeps deterministic ordering by writing indexed results.
		local ci_tmp fail_marker
		ci_tmp="$(mktemp -d -t spec_ci_XXXXXX)"
		fail_marker="$ci_tmp/fail.marker"
		local pids=()
		local idx=0
		local launched=0
		local f idx_this f_this

		for f in "${scan_files[@]}"; do
			if $fail_fast && [[ -f "$fail_marker" ]]; then
				truncated=true
				truncated_reason="fail-fast"
				break
			fi

			idx_this="$idx"
			f_this="$f"
			(
				if validate_file_quiet "$f_this" "$strict"; then
					echo "pass" > "$ci_tmp/$idx_this.result"
				else
					echo "fail" > "$ci_tmp/$idx_this.result"
					if $fail_fast; then
						: > "$fail_marker"
					fi
				fi
				echo "$f_this" > "$ci_tmp/$idx_this.file"
			) &

			pids+=("$!")
			launched=$((launched + 1))
			idx=$((idx + 1))

			if [[ "${#pids[@]}" -ge "$jobs" ]]; then
				wait "${pids[0]}" 2>/dev/null || true
				pids=("${pids[@]:1}")
			fi
		done

		local pid
		for pid in "${pids[@]}"; do
			wait "$pid" 2>/dev/null || true
		done

		idx=0
		while [[ "$idx" -lt "$launched" ]]; do
			f_this="$(cat "$ci_tmp/$idx.file" 2>/dev/null || echo "")"
			local state
			state="$(cat "$ci_tmp/$idx.result" 2>/dev/null || echo "fail")"
			if [[ -n "$f_this" ]]; then
				total=$((total + 1))
				if [[ "$state" == "pass" ]]; then
					passed=$((passed + 1))
				else
					failed=$((failed + 1))
					failures+=("$f_this")
				fi
			fi
			idx=$((idx + 1))
		done

		if [[ "$launched" -lt "${#scan_files[@]}" ]]; then
			truncated=true
			[[ -z "$truncated_reason" ]] && truncated_reason="fail-fast"
		fi

		rm -rf "$ci_tmp" 2>/dev/null || true
	fi

	local truncated_json="false"
	$truncated && truncated_json="true"

	case "$format" in
		json)
			if [[ "$failed" -eq 0 ]]; then
				echo "{\"total\": $total, \"passed\": $passed, \"failed\": $failed, \"failures\": [], \"truncated\": $truncated_json}"
			else
				echo "{\"total\": $total, \"passed\": $passed, \"failed\": $failed, \"failures\": ["
				local first=true
				for ff in "${failures[@]}"; do
					$first || echo ","
					echo -n "    \"$ff\""
					first=false
				done
				echo ""
				echo "], \"truncated\": $truncated_json}"
			fi
			;;
		github)
			if [[ "$failed" -gt 0 ]]; then
				for ff in "${failures[@]}"; do
					echo "::error file=$ff::Spec validation failed"
				done
			fi
			echo "::notice::Spec CI: $passed/$total passed"
			[[ "$jobs" -gt 1 ]] && echo "::notice::Spec CI used parallel validation (--jobs=$jobs)"
			if $truncated; then
				if [[ "$truncated_reason" == "max-files" ]]; then
					echo "::notice::Spec CI scan truncated at --max-files=$max_files"
				else
					echo "::notice::Spec CI scan truncated due to fail-fast"
				fi
			fi
			;;
		*)
			echo "spec ci: $passed passed, $failed failed, $total total"
			[[ "$jobs" -gt 1 ]] && echo "  NOTE: parallel validation enabled (--jobs=$jobs)"
			if [[ "$failed" -gt 0 ]]; then
				for ff in "${failures[@]}"; do
					echo "  FAIL: $ff"
				done
			fi
			if $truncated; then
				if [[ "$truncated_reason" == "max-files" ]]; then
					echo "  NOTE: scan truncated at --max-files=$max_files"
				else
					echo "  NOTE: scan truncated due to fail-fast"
				fi
			fi
			$fail_fast && [[ "$failed" -gt 0 ]] && echo "  NOTE: fail-fast triggered on first failure"
			;;
	esac
	return $failed
}

spec_cmd_template() {
	local sub="${1:-list}"
	shift 2>/dev/null || true

	local template_dir="$PROJECT_DIR/specs/templates"
	local user_template_dir="$HOME/.config/kujo-spec/templates"
	mkdir -p "$user_template_dir" 2>/dev/null || true

	case "$sub" in
		list)
			echo "Project templates ($template_dir):"
			local project_names
			project_names="$(find "$template_dir" -maxdepth 1 -type f \( -name '*.template.yml' -o -name '*.template.json' \) 2>/dev/null | sed -e 's#.*/##' -e 's/\.template\.yml$//' -e 's/\.template\.json$//' | sort -u)" || project_names=""
			if [[ -n "$project_names" ]]; then
				while IFS= read -r name; do
					[[ -n "$name" ]] && echo "  $name"
				done <<< "$project_names"
			else
				echo "  (none)"
			fi
			echo ""
			echo "User templates ($user_template_dir):"
			local user_names
			user_names="$(find "$user_template_dir" -maxdepth 1 -type f \( -name '*.template.yml' -o -name '*.template.json' \) 2>/dev/null | sed -e 's#.*/##' -e 's/\.template\.yml$//' -e 's/\.template\.json$//' | sort -u)" || user_names=""
			if [[ -n "$user_names" ]]; then
				while IFS= read -r name; do
					[[ -n "$name" ]] && echo "  $name"
				done <<< "$user_names"
			else
				echo "  (none)"
			fi
			;;
		create)
			local src="${1:-}" name="${2:-}"
			[[ -z "$src" || -z "$name" ]] && die "Usage: spec template create <spec-file> <template-name>"
			[[ -f "$src" ]] || die "Source spec not found: $src"
			mkdir -p "$user_template_dir" 2>/dev/null || true
			cp "$src" "$user_template_dir/${name}.template.yml"
			echo "Template created: $user_template_dir/${name}.template.yml"
			;;
		delete)
			local name="${1:-}"
			[[ -z "$name" ]] && die "Usage: spec template delete <template-name>"
			local tfile="$user_template_dir/${name}.template.yml"
			[[ -f "$tfile" ]] || tfile="$user_template_dir/${name}.template.json"
			[[ -f "$tfile" ]] || die "Template not found: $name"
			rm -f "$tfile"
			echo "Deleted: $name"
			;;
		*) die "Usage: spec template <list|create|delete> [args...]" ;;
	esac
}

spec_cmd_export_unified() {
	local f="${1:-}" out="" fmt="agent" payload_format="agent" unsafe_write=false
	local unsafe_opt=""
	while [[ $# -gt 0 ]]; do case "$1" in
		--output) out="$2"; shift 2 ;; --format) fmt="$2"; shift 2 ;;
		--payload-format) payload_format="$2"; shift 2 ;;
		--unsafe-write) unsafe_write=true; shift ;;
		*) shift ;;
	esac; done
	[[ -z "$f" ]] && die "Usage: spec export <file> [--format agent|dispatch|markdown|eval|envelope] [--payload-format agent|dispatch] [--output <path>]"
	[[ -f "$f" ]] || die "File not found: $f"
	is_safe_path "$f" || exit 1
	if [[ "$unsafe_write" == "true" ]]; then
		unsafe_opt="--unsafe-write"
	fi

	case "$fmt" in
		agent|dispatch) cmd_export "$f" --format "$fmt" ${out:+--output "$out"} ${unsafe_opt:+$unsafe_opt} ;;
		markdown) cmd_render "$f" ${out:+--output "$out"} ${unsafe_opt:+$unsafe_opt} ;;
		eval) cmd_export_eval "$f" ${out:+--output "$out"} ${unsafe_opt:+$unsafe_opt} ;;
		envelope)
			[[ "$payload_format" =~ ^(agent|dispatch)$ ]] || die "Invalid --payload-format: $payload_format (use agent or dispatch)"
			local tmp payload source_abs checksum generated_at schema_version envelope_json
			tmp="$(mktemp -t spec_export_env_XXXXXX.json)"
			trap "rm -f $tmp" RETURN
			spec_to_json "$f" "$tmp"
			payload="$(run_kujo run "$PROJECT_DIR/src/export.kujo" --json "$tmp" --format "$payload_format" 2>/dev/null)" || true
			source_abs="$(python3 -c 'import os,sys; print(os.path.abspath(sys.argv[1]))' "$f" 2>/dev/null || echo "$f")"
			checksum="$(shasum -a 256 "$f" 2>/dev/null | awk '{print $1}')"
			generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "")"
			schema_version="${SPEC_SCHEMA_VERSION:-1.0.0}"
			envelope_json="$(python3 -c '
import json, sys
source_file = sys.argv[1]
schema_version = sys.argv[2]
checksum = sys.argv[3]
generated_at = sys.argv[4]
payload_format = sys.argv[5]
raw_payload = sys.argv[6]
payload = raw_payload
if payload_format == "dispatch":
    try:
        payload = json.loads(raw_payload)
    except Exception:
        payload = raw_payload
out = {
    "metadata": {
        "source_file": source_file,
        "schema_version": schema_version,
        "checksum_sha256": checksum,
        "generated_at": generated_at,
        "payload_format": payload_format
    },
    "payload": payload
}
print(json.dumps(out, indent=2))
' "$source_abs" "$schema_version" "$checksum" "$generated_at" "$payload_format" "$payload")"
			if [[ -n "$out" ]]; then
				enforce_safe_write_path "$out" "$unsafe_write"
				echo "$envelope_json" > "$out"
				echo "Exported: $out"
			else
				echo "$envelope_json"
			fi
			;;
		*) die "Unknown format: $fmt. Use agent, dispatch, markdown, eval, or envelope." ;;
	esac
}

spec_cmd_init_interactive() {
	echo "=== Spec Interactive Creator ==="
	echo "Press Enter to accept defaults."
	echo ""

	local name goal priority tags
	echo -n "Name: "
	read -r name
	[[ -z "$name" ]] && die "Name is required."

	echo -n "Goal: "
	read -r goal

	echo -n "Priority [medium]: "
	read -r priority
	priority="${priority:-medium}"
	[[ "$priority" =~ ^(critical|high|medium|low)$ ]] || { echo "Invalid priority. Using medium."; priority="medium"; }

	echo -n "Tags (comma-separated): "
	read -r tags

	local out="spec.yml"
	echo -n "Output file [spec.yml]: "
	read -r out_override
	out="${out_override:-$out}"

	[[ -f "$out" ]] && die "File exists: $out"
	enforce_safe_write_path "$out" false

	# Create spec with collected values
	local uuid; uuid="$(python3 -c "import uuid; print(str(uuid.uuid4()))" 2>/dev/null)" || uuid="00000000-0000-4000-8000-000000000000"
	local now; now="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)" || now=""

	# Convert comma-separated tags to YAML array
	local tags_yaml="[]"
	if [[ -n "$tags" ]]; then
		tags_yaml="[$(echo "$tags" | sed 's/, */", "/g' | sed 's/^/"/;s/$/"/')]"
	fi

	cat > "$out" <<YMLEOF
name: "$name"
goal: "$goal"
id: "$uuid"
status: "draft"
version: "0.1.0"
created_at: "$now"
priority: "$priority"
tags: $tags_yaml
YMLEOF

	echo ""
	echo "Created: $out"
	echo "Run 'spec validate $out' to verify."
}

spec_cmd_doctor() {
	echo "=== Spec Doctor ==="
	echo ""

	# Check Kujo runtime
	echo -n "Kujo runtime: "
	if [[ -n "$KUJO_BIN" ]] && [[ -x "$KUJO_BIN" ]]; then
		echo "✅ $KUJO_BIN"
	elif command -v kujo &>/dev/null; then
		echo "✅ $(command -v kujo) (from PATH)"
	else
		echo "❌ Not found"
		echo "   Fix: export KUJO_BIN=/path/to/kujo/target/release/kujo"
	fi

	# Check Python 3
	echo -n "Python 3:     "
	if command -v python3 &>/dev/null; then
		echo "✅ $(python3 --version 2>&1)"
	else
		echo "❌ Not found"
	fi

	# Check PyYAML
	echo -n "PyYAML:       "
	if python3 -c "import yaml" 2>/dev/null; then
		echo "✅ installed"
	else
		echo "⚠️  Not installed (needed for YAML specs)"
		echo "   Fix: pip3 install pyyaml"
	fi

	# Check spec script
	echo -n "Spec CLI:     "
	if [[ -x "$SCRIPT_DIR/spec" ]]; then
		echo "✅ $SCRIPT_DIR/spec"
	else
		echo "❌ Not executable"
	fi

	# Check source files
	echo -n "Kujo modules: "
	local missing=0
	for m in validate render export common; do
		[[ -f "$PROJECT_DIR/src/${m}.kujo" ]] || missing=$((missing + 1))
	done
	if [[ $missing -eq 0 ]]; then
		echo "✅ 4 modules found"
	else
		echo "❌ $missing module(s) missing"
	fi

	# Check schema
	echo -n "JSON Schema:  "
	if [[ -f "$PROJECT_DIR/schema/spec.schema.json" ]]; then
		echo "✅ Found"
	else
		echo "❌ Missing"
	fi

	# Check common locations for specs
	echo ""
	echo "Spec files found:"
	local count; count="$(find . -maxdepth 3 -name '*.spec.yml' -o -name '*.spec.yaml' -o -name '*.spec.toml' -o -name '*.spec.json' 2>/dev/null | wc -l | tr -d ' ')" || count=0
	echo "  $count spec(s) in current directory tree"

	echo ""
	echo "Environment:"
	echo "  KUJO_BIN:     ${KUJO_BIN:-not set}"
	echo "  SPEC_TIMEOUT: ${SPEC_TIMEOUT:-30}s"
	echo "  SHELL:        ${SHELL:-unknown}"
	echo "  OS:           $(uname -s)"
}

spec_cmd_changelog() {
	local since="${1:-}"
	if [[ -z "$since" ]]; then
		# Default: since last tag
		since="$(git describe --tags --abbrev=0 2>/dev/null)" || since=""
		if [[ -z "$since" ]]; then
			since="$(git rev-list --max-parents=0 HEAD 2>/dev/null | tail -n 1)" || since=""
			[[ -n "$since" ]] && echo "No tags found. Using repository root commit: $since"
		fi
	fi
	[[ -z "$since" ]] && die "Could not determine changelog base. Specify a ref: spec changelog <tag-or-commit>"

	echo "## Changelog ($since..HEAD)"
	echo ""

	# Group by conventional commit type
	echo "### Features"
	git log "$since..HEAD" --oneline --no-merges 2>/dev/null | grep -iE 'feat:|feature:' | sed 's/^/- /' || echo "  (none)"

	echo ""
	echo "### Fixes"
	git log "$since..HEAD" --oneline --no-merges 2>/dev/null | grep -iE 'fix:|bug:' | sed 's/^/- /' || echo "  (none)"

	echo ""
	echo "### Performance"
	git log "$since..HEAD" --oneline --no-merges 2>/dev/null | grep -iE 'perf:|performance:' | sed 's/^/- /' || echo "  (none)"

	echo ""
	echo "### Security"
	git log "$since..HEAD" --oneline --no-merges 2>/dev/null | grep -iE 'sec:|security:' | sed 's/^/- /' || echo "  (none)"

	echo ""
	echo "### Documentation"
	git log "$since..HEAD" --oneline --no-merges 2>/dev/null | grep -iE 'docs:|doc:' | sed 's/^/- /' || echo "  (none)"

	echo ""
	echo "### Other"
	git log "$since..HEAD" --oneline --no-merges 2>/dev/null | grep -viE 'feat:|fix:|perf:|sec:|docs:|feature:|bug:|performance:|security:|doc:' | sed 's/^/- /' || echo "  (none)"
}

spec_cmd_graph() {
	local dir="${1:-.}" format="mermaid"
	while [[ $# -gt 0 ]]; do case "$1" in
		--format) format="$2"; shift 2 ;; *) shift ;;
	esac; done

	# Collect all specs and their relationships
	local files
	files="$(find "$dir" -maxdepth 5 -type f \( -name '*.spec.yml' -o -name '*.spec.yaml' -o -name '*.spec.toml' -o -name '*.spec.json' \) 2>/dev/null | sort)" || true
	[[ -z "$files" ]] && die "No spec files found"

	# Build a graph from spec parent_id relationships
	local tmpdir; tmpdir="$(mktemp -d)"
	trap "rm -rf $tmpdir" RETURN
	local idx=0
	local spec_names=()
	local spec_parents=()
	local spec_ids=()

	while IFS= read -r f; do
		[[ -z "$f" ]] && continue
		local jf="$tmpdir/$(printf '%04d' $idx).json"
		spec_to_json "$f" "$jf" 2>/dev/null || continue
		local name pid sid
		name="$(python3 "$HELPER" get "$jf" name "?" 2>/dev/null)" || name="?"
		pid="$(python3 "$HELPER" get "$jf" parent_id "" 2>/dev/null)" || pid=""
		sid="$(python3 "$HELPER" get "$jf" id "" 2>/dev/null)" || sid=""
		spec_names+=("$name")
		spec_parents+=("$pid")
		spec_ids+=("$sid")
		idx=$((idx + 1))
	done <<< "$files"

	case "$format" in
		mermaid)
			echo '```mermaid'
			echo 'graph TD'
			local i=0
			while [[ $i -lt $idx ]]; do
				local n="${spec_names[$i]}"
				local p="${spec_parents[$i]}"
				echo "    spec$i[\"$n\"]"
				if [[ -n "$p" ]]; then
					# Find parent index
					local j=0
					while [[ $j -lt $idx ]]; do
						if [[ "${spec_ids[$j]}" == "$p" ]]; then
							echo "    spec$j --> spec$i"
							break
						fi
						j=$((j + 1))
					done
				fi
				i=$((i + 1))
			done
			echo '```'
			;;
		dot)
			echo 'digraph Specs {'
			echo '  rankdir=TB;'
			echo '  node [shape=box, style=rounded];'
			local i=0
			while [[ $i -lt $idx ]]; do
				local n="${spec_names[$i]}"
				echo "  spec$i [label=\"$n\"];"
				i=$((i + 1))
			done
			# Edges
			i=0
			while [[ $i -lt $idx ]]; do
				local p="${spec_parents[$i]}"
				if [[ -n "$p" ]]; then
					local j=0
					while [[ $j -lt $idx ]]; do
						if [[ "${spec_ids[$j]}" == "$p" ]]; then
							echo "  spec$j -> spec$i;"
							break
						fi
						j=$((j + 1))
					done
				fi
				i=$((i + 1))
			done
			echo '}'
			;;
		*) die "Unknown format: $format. Use mermaid or dot." ;;
	esac
}
