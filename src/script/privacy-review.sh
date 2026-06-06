#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib/frontmatter.sh
. "${SCRIPT_DIR}/lib/frontmatter.sh"
# shellcheck source=lib/json.sh
. "${SCRIPT_DIR}/lib/json.sh"
# shellcheck source=lib/paths.sh
. "${SCRIPT_DIR}/lib/paths.sh"

usage() {
    cat <<'USAGE'
Usage: privacy-review.sh [--vault PATH] [--json]

Warn about private-data patterns. This command is warning-only and exits 0.
USAGE
}

json=false

while [ "$#" -gt 0 ]; do
    case "$1" in
        --vault) STRATA_VAULT=$2; export STRATA_VAULT; shift 2 ;;
        --json) json=true; shift ;;
        --help|-h) usage; exit 0 ;;
        *) printf '%s\n' "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

vault=$(strata_vault)
tmp_dir="${vault}/0_core/tmp"
mkdir -p "$tmp_dir"

warnings_tmp=$(mktemp "${tmp_dir}/privacy-warnings-XXXXXXXX")
files_tmp=$(mktemp "${tmp_dir}/privacy-files-XXXXXXXX")
trap 'rm -f "$warnings_tmp" "$files_tmp"' EXIT HUP INT TERM
: > "$warnings_tmp"
: > "$files_tmp"

emit_warning() {
    local reason=$1
    local path=$2
    local line=$3
    local detail=$4
    printf '%s\t%s\t%s\t%s\n' "$reason" "$path" "$line" "$detail" >> "$warnings_tmp"
}

collect_files() {
    find "$vault/1_draft" "$vault/2_knowledge" "$vault/3_intelligence" \
        -type f \( -name '*.md' -o -name '*.txt' -o -name '*.yaml' -o -name '*.yml' -o -name '*.json' -o -name '.env' \) \
        2>/dev/null
    [ -f "$vault/AGENTS.md" ] && printf '%s\n' "$vault/AGENTS.md"
}

collect_files | sort > "$files_tmp"

while IFS= read -r file; do
    [ -n "$file" ] || continue
    rel=$(strata_rel_path "$file" "$vault")

    awk -v rel="$rel" '
    function emit(reason, detail) {
      printf "%s\t%s\t%d\t%s\n", reason, rel, NR, detail
    }
    /file:\/\// {
      emit("file_url", "file:// links expose local machine paths")
    }
    /(^|[^A-Za-z0-9_\/])(\/home\/[A-Za-z0-9._-]+|\/Users\/[A-Za-z0-9._-]+|\/root)(\/|$)/ {
      emit("absolute_home_path", "absolute home path found")
    }
    /-----BEGIN [A-Z ]*PRIVATE KEY-----/ {
      emit("private_ssh_key", "private key block found")
    }
    /^[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*(SECRET|TOKEN|PASSWORD|PASS|API_KEY|ACCESS_KEY|PRIVATE_KEY)[A-Za-z0-9_]*[[:space:]]*=/ {
      emit("env_secret", "environment-style secret assignment found")
    }
    /(api[_-]?key|access[_-]?token|secret|password|bearer)[[:space:]]*[:=][[:space:]]*["'\''"]?[A-Za-z0-9_\/+=.-]{20,}/ {
      emit("api_key_like", "API-key-like assignment found")
    }
    /sk-[A-Za-z0-9]{20,}/ {
      emit("api_key_like", "sk-prefixed token found")
    }
    /\b(TRACE|DEBUG|INFO|WARN|WARNING|ERROR|FATAL)\b/ {
      log_lines++
    }
    END {
      if (NR > 1200 && log_lines > 100) {
        printf "%s\t%s\t%d\t%s\n", "large_pasted_log", rel, 1, "large log-like file found"
      }
    }
    ' "$file" >> "$warnings_tmp"
done < "$files_tmp"

warning_count=$(wc -l < "$warnings_tmp" | awk '{print $1}')

if [ "$json" = true ]; then
    printf '{"ok":true,"warning_count":%s,"warnings":[' "$warning_count"
    first=true
    while IFS="$(printf '\t')" read -r reason path line detail; do
        [ -n "$reason" ] || continue
        if [ "$first" = true ]; then first=false; else printf ','; fi
        printf '{"severity":"warn","reason":'; strata_json_string "$reason"
        printf ',"path":'; strata_json_string "$path"
        printf ',"line":%s,"detail":' "$line"
        strata_json_string "$detail"
        printf '}'
    done < "$warnings_tmp"
    printf ']}\n'
else
    if [ "$warning_count" = "0" ]; then
        printf 'No privacy warnings found\n'
    else
        printf 'Privacy warnings:\n'
        awk -F '\t' '{ printf "warn %s %s:%s - %s\n", $1, $2, $3, $4 }' "$warnings_tmp"
    fi
fi

exit 0
