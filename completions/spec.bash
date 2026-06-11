_spec_completions() {
	local cur="${COMP_WORDS[COMP_CWORD]}"
	local prev="${COMP_WORDS[COMP_CWORD-1]}"
	local cmds="init create init-interactive validate render export export-agent-context info list validate-all search status convert template watch diff export-eval ci doctor changelog graph version help"
	local formats="yaml toml json agent dispatch markdown eval envelope mermaid dot"
	local statuses="draft ready in-progress review completed archived"

	if [[ $COMP_CWORD -eq 1 ]]; then
		COMPREPLY=($(compgen -W "$cmds" -- "$cur"))
		return
	fi

	case "$prev" in
		--format) COMPREPLY=($(compgen -W "$formats" -- "$cur")); return ;;
		--payload-format) COMPREPLY=($(compgen -W "agent dispatch" -- "$cur")); return ;;
		--to) COMPREPLY=($(compgen -W "$formats" -- "$cur")); return ;;
		--set) COMPREPLY=($(compgen -W "$statuses" -- "$cur")); return ;;
		--from) COMPREPLY=($(compgen -W "json: template: github: -" -- "$cur")); return ;;
		--template-source-policy) COMPREPLY=($(compgen -W "allow-home project-only" -- "$cur")); return ;;
		--priority) COMPREPLY=($(compgen -W "critical high medium low" -- "$cur")); return ;;
		validate|render|export-agent-context|export|status|convert|watch|diff|export-eval|info)
			COMPREPLY=($(compgen -f -- "$cur" | grep -E '\.(spec\.)?(yml|yaml|toml|json)$'))
			return ;;
	esac
	COMPREPLY=($(compgen -W "--format --payload-format --output --name --from --to --set --priority --tag --query --quiet --json --strict --max-depth --dir --max-files --fail-fast --jobs --unsafe-write --strict-template-source" -- "$cur"))
}
complete -F _spec_completions spec
