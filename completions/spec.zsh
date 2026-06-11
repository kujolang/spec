#compdef spec
_spec() {
	local -a cmds=(init create init-interactive validate render export export-agent-context info list validate-all search status convert template watch diff export-eval ci doctor changelog graph version help)
	_arguments \
		'1: :($cmds)' \
		'--format[Output format]:format:(yaml toml json agent dispatch markdown eval envelope mermaid dot)' \
		'--payload-format[Envelope payload format]:payload:(agent dispatch)' \
		'--output[Output path]:file:_files' \
		'--name[Spec name]:name:' \
		'--from[Init source]:source:' \
		'--to[Convert target]:format:(yaml toml json)' \
		'--set[Spec status]:status:(draft ready in-progress review completed archived)' \
		'--priority[Priority filter]:priority:(critical high medium low)' \
		'--tag[Tag filter]:tag:' \
		'--query[Search query]:query:' \
		'--max-depth[Directory scan depth]:depth:' \
		'--dir[Directory]:dir:_files -/' \
		'--max-files[Max files for ci]:count:' \
		'--jobs[Parallel ci workers]:count:' \
		'--json[JSON output]' \
		'--quiet[Suppress success output]' \
		'--strict[Treat warnings as errors]' \
		'--fail-fast[Stop ci on first failure]' \
		'--unsafe-write[Allow writing outside project root]' \
		'--strict-template-source[Restrict template loading to project templates]' \
		'*:: :_files'
}
_spec
