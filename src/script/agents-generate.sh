#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib/config.sh
. "${SCRIPT_DIR}/lib/config.sh"
# shellcheck source=lib/json.sh
. "${SCRIPT_DIR}/lib/json.sh"
# shellcheck source=lib/log.sh
. "${SCRIPT_DIR}/lib/log.sh"
# shellcheck source=lib/paths.sh
. "${SCRIPT_DIR}/lib/paths.sh"

usage() {
    cat <<'USAGE'
Usage: agents-generate.sh [--vault PATH] [--json]

Generate vault AGENTS.md from templates and config while preserving manual sections.
USAGE
}

json=false

while [ "$#" -gt 0 ]; do
    case "$1" in
        --vault)
            STRATA_VAULT=$2
            export STRATA_VAULT
            shift 2
            ;;
        --json)
            json=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            printf '%s\n' "Unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

vault=$(strata_vault)
core=$(strata_core)
target="${vault}/AGENTS.md"
base="${core}/template/agents/base.md"
tmp_root="${core}/tmp"
mkdir -p "$tmp_root"

[ -f "$base" ] || { strata_log_error "missing AGENTS base template: $base"; exit 1; }
[ -f "$(strata_config_path)" ] || { strata_log_error "missing config: $(strata_config_path)"; exit 1; }

manual_tmp=$(mktemp "${tmp_root}/agents-manual-XXXXXXXX")
generated_tmp=$(mktemp "${tmp_root}/agents-generated-XXXXXXXX")
output_tmp=$(mktemp "${tmp_root}/agents-output-XXXXXXXX")
trap 'rm -f "$manual_tmp" "$generated_tmp" "$output_tmp"' EXIT HUP INT TERM

extract_manual() {
    local file=$1
    awk '
    /<!-- STRATA_MANUAL_START -->/ { print; in_manual = 1; next }
    /<!-- STRATA_MANUAL_END -->/ { print; in_manual = 0; found = 1; next }
    in_manual { print }
    END { if (!found) exit 1 }
    ' "$file"
}

if [ -f "$target" ] && extract_manual "$target" > "$manual_tmp"; then
    :
elif extract_manual "$base" > "$manual_tmp"; then
    :
else
    {
        printf '%s\n' '<!-- STRATA_MANUAL_START -->'
        printf '%s\n' 'Add vault-specific instructions here.'
        printf '%s\n' '<!-- STRATA_MANUAL_END -->'
    } > "$manual_tmp"
fi

profile=$(strata_config_profile)
[ -n "$profile" ] || profile=default

{
    printf '%s\n' '<!-- STRATA_GENERATED_START -->'
    printf '%s\n' '## Structure'
    printf '%s\n\n' '```text'
    printf '%s\n' '0_core/            Kernel: config, scripts, schema, templates, docs, cache, tmp.'
    printf '%s\n' '1_draft/           Tier 1: raw, unreviewed, ephemeral material.'
    printf '%s\n' '2_knowledge/       Tier 2: curated, reviewed, durable knowledge.'
    printf '%s\n' '3_intelligence/    Tier 3: skills, agents, workflows, and generated reports.'
    printf '%s\n\n' '```'
    printf '## Active Profile\n\n'
    printf 'Profile: `%s`\n\n' "$profile"
    profile_template="${core}/template/agents/profile/${profile}.md"
    if [ -f "$profile_template" ]; then
        sed -n '1,$p' "$profile_template"
        printf '\n'
    fi
    printf '## Registered Tier 2 Rooms\n\n'
    strata_config_profile_tier2_rooms "$profile" | while IFS= read -r room; do
        [ -n "$room" ] || continue
        printf -- '- `%s`\n' "$room"
    done
    printf '\n'
    printf '## Strata Commands\n\n'
    printf 'Core commands are namespaced in generated command tables.\n\n'
    printf '| Command | Usage |\n'
    printf '|---|---|\n'
    printf '| `strata:init` | Initialize vault structure and bootstrap config. |\n'
    printf '| `strata:doctor` | Check vault health, dependencies, config, schema, rooms, tags, and generated files. |\n'
    printf '| `strata:index` | Index target files or run a full scan. |\n'
    printf '| `strata:search` | Search indexed memory. |\n'
    printf '| `strata:promote` | Promote drafts into knowledge or intelligence. |\n'
    printf '| `strata:tag-review` | Review unknown or similar tags. |\n'
    printf '| `strata:room-review` | Review unregistered rooms. |\n'
    printf '| `strata:link-review` | Review invalid or broken vault links. |\n'
    printf '| `strata:migrate` | Migrate selected sections from `~/.agent-knowledge/memory`. |\n'
    printf '| `strata:agents-generate` | Generate `AGENTS.md` from templates, profile, config, and manual sections. |\n'
    printf '\nFull generated command docs live at `0_core/doc/commands.md`.\n'
    printf '%s\n' '<!-- STRATA_GENERATED_END -->'
} > "$generated_tmp"

awk -v generated="$generated_tmp" -v manual="$manual_tmp" '
function dump(path) {
  while ((getline line < path) > 0) print line
  close(path)
}
/<!-- STRATA_GENERATED_START -->/ {
  dump(generated)
  in_generated = 1
  next
}
/<!-- STRATA_GENERATED_END -->/ {
  in_generated = 0
  next
}
/<!-- STRATA_MANUAL_START -->/ {
  dump(manual)
  in_manual = 1
  next
}
/<!-- STRATA_MANUAL_END -->/ {
  in_manual = 0
  next
}
in_generated || in_manual { next }
{ print }
' "$base" > "$output_tmp"

mv "$output_tmp" "$target"
trap - EXIT HUP INT TERM
rm -f "$manual_tmp" "$generated_tmp"

if [ "$json" = true ]; then
    printf '{"ok":true,"path":"AGENTS.md","profile":'
    strata_json_string "$profile"
    printf '}\n'
else
    printf 'Generated AGENTS.md for profile: %s\n' "$profile"
fi
