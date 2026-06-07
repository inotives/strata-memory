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
Usage: migration.sh [--from PATH] [--to PATH] [--section NAME | --all] [--json]

Migrate selected sections from legacy Agent Memory into a Strata vault.
Sections: config, knowledge, intelligence, agents-md.
USAGE
}

from=${STRATA_LEGACY_MEMORY:-"${HOME}/.agent-knowledge/memory"}
to=${STRATA_VAULT:-"${HOME}/.strata-memory"}
section=
all=false
json=false

while [ "$#" -gt 0 ]; do
    case "$1" in
        --from) from=$2; shift 2 ;;
        --to|--vault) to=$2; shift 2 ;;
        --section) section=$2; shift 2 ;;
        --all) all=true; shift ;;
        --json) json=true; shift ;;
        --help|-h) usage; exit 0 ;;
        *) printf '%s\n' "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$from" in /*) ;; *) from=$(CDPATH= cd -- "$from" && pwd) ;; esac
case "$to" in /*) ;; *) to=$(CDPATH= cd -- "$to" && pwd) ;; esac

if [ "$all" = true ] && [ -n "$section" ]; then
    printf '%s\n' "Use either --section or --all, not both." >&2
    exit 2
fi

if [ "$all" = false ] && [ -z "$section" ]; then
    usage >&2
    exit 2
fi

if [ ! -d "$from" ]; then
    printf 'Legacy memory not found: %s\n' "$from" >&2
    exit 1
fi

if [ ! -d "$to/0_core" ]; then
    printf 'Strata vault not initialized: %s\n' "$to" >&2
    exit 1
fi

case "$to" in
    "$from"|"$from"/*)
        printf 'Target vault must not be inside legacy memory: %s\n' "$to" >&2
        exit 1
        ;;
esac

STRATA_VAULT=$to
export STRATA_VAULT

tmp_dir="$to/0_core/tmp"
report_dir="$to/3_intelligence/report/migration"
mkdir -p "$tmp_dir" "$report_dir"

plan_tmp=$(mktemp "$tmp_dir/migration-plan-XXXXXXXX")
map_tmp=$(mktemp "$tmp_dir/migration-map-XXXXXXXX")
records_tmp=$(mktemp "$tmp_dir/migration-records-XXXXXXXX")
content_dir=$(mktemp -d "$tmp_dir/migration-content-XXXXXXXX")
trap 'rm -f "$plan_tmp" "$map_tmp" "$records_tmp"; rm -rf "$content_dir"' EXIT HUP INT TERM
: > "$plan_tmp"
: > "$map_tmp"
: > "$records_tmp"

slugify_path() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[ _][ _]*/-/g; s/[^a-z0-9.*_\/-]/-/g; s/-\{2,\}/-/g; s#/\{2,\}#/#g; s#^\./##'
}

map_component() {
    local component
    component=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
    case "$component" in
        2_knowledges) printf '%s\n' "2_knowledge" ;;
        3_intelligences) printf '%s\n' "3_intelligence" ;;
        concepts) printf '%s\n' "concept" ;;
        entities) printf '%s\n' "entity" ;;
        projects) printf '%s\n' "project" ;;
        tools) printf '%s\n' "tool" ;;
        companies) printf '%s\n' "company" ;;
        stocks) printf '%s\n' "stock" ;;
        cryptocurrencies|cryptos) printf '%s\n' "cryptocurrency" ;;
        researches) printf '%s\n' "research" ;;
        notes) printf '%s\n' "note" ;;
        preferences) printf '%s\n' "preference" ;;
        skills) printf '%s\n' "skill" ;;
        agents) printf '%s\n' "agent" ;;
        workflows) printf '%s\n' "workflow" ;;
        reports) printf '%s\n' "report" ;;
        news) printf '%s\n' "_unmapped/news" ;;
        source|sources) printf '%s\n' "_unmapped/sources" ;;
        *) slugify_path "$1" ;;
    esac
}

map_legacy_rel() {
    local rel=$1
    local first rest out part mapped
    first=${rel%%/*}
    rest=
    case "$rel" in */*) rest=${rel#*/} ;; esac

    case "$first" in
        2_knowledges|3_intelligences) out=$(map_component "$first") ;;
        *) return 1 ;;
    esac

    while [ -n "$rest" ]; do
        part=${rest%%/*}
        case "$rest" in */*) rest=${rest#*/} ;; *) rest= ;; esac
        mapped=$(map_component "$part")
        out="${out}/${mapped}"
    done

    case "$out" in
        2_knowledge/*|3_intelligence/*) printf '%s\n' "$out" ;;
        *) return 1 ;;
    esac
}

record() {
    local kind=$1 old_rel=$2 new_rel=$3 detail=$4
    printf '%s\t%s\t%s\t%s\n' "$kind" "$old_rel" "$new_rel" "$detail" >> "$records_tmp"
}

plan_file() {
    local old_abs=$1
    local old_rel=$2
    local new_rel
    case "$old_rel" in
        1_drafts/*)
            record skipped "$old_rel" "" "legacy drafts are not migrated"
            return 0
            ;;
    esac

    if new_rel=$(map_legacy_rel "$old_rel"); then
        case "$new_rel" in
            2_knowledge/entity/project/*|2_knowledge/entity/tool/*|2_knowledge/entity/company/*|2_knowledge/entity/stock/*|2_knowledge/entity/cryptocurrency/*)
                record mapped "$old_rel" "$new_rel" "canonical mapping"
                ;;
            2_knowledge/entity/*)
                new_rel="2_knowledge/_unmapped/entity/${new_rel#2_knowledge/entity/}"
                record unmapped "$old_rel" "$new_rel" "unknown entity bucket requires review"
                ;;
            2_knowledge/concept/*|2_knowledge/research/*|2_knowledge/note/*|2_knowledge/preference/*|3_intelligence/skill/*|3_intelligence/agent/*|3_intelligence/workflow/*|3_intelligence/report/*)
                record mapped "$old_rel" "$new_rel" "canonical mapping"
                ;;
            2_knowledge/_unmapped/*)
                record unmapped "$old_rel" "$new_rel" "knowledge room requires review"
                ;;
            2_knowledge/*)
                file_name=$(basename -- "$new_rel")
                new_rel="2_knowledge/_unmapped/${new_rel#2_knowledge/}"
                record unmapped "$old_rel" "$new_rel" "knowledge room requires review"
                ;;
            *)
                record mapped "$old_rel" "$new_rel" "canonical mapping"
                ;;
        esac
    else
        file_name=$(basename -- "$old_rel")
        new_rel="2_knowledge/_unmapped/$(slugify_path "$file_name")"
        record unmapped "$old_rel" "$new_rel" "unmatched legacy path"
    fi
    printf '%s\t%s\t%s\n' "$old_abs" "$old_rel" "$new_rel" >> "$plan_tmp"
    printf '%s\t%s\n' "$old_rel" "$new_rel" >> "$map_tmp"
}

plan_section() {
    local selected=$1
    case "$selected" in
        config)
            if [ -d "$from/0_configs" ]; then
                find "$from/0_configs" -type f -name '*.md' 2>/dev/null | sort | while IFS= read -r file; do
                    rel=${file#"$from"/}
                    new_rel="2_knowledge/_unmapped/config/$(slugify_path "${rel#0_configs/}")"
                    record unmapped "$rel" "$new_rel" "legacy config material requires review"
                    printf '%s\t%s\t%s\n' "$file" "$rel" "$new_rel" >> "$plan_tmp"
                    printf '%s\t%s\n' "$rel" "$new_rel" >> "$map_tmp"
                done
            fi
            ;;
        knowledge)
            if [ -d "$from/2_knowledges" ]; then
                find "$from/2_knowledges" -type f -name '*.md' 2>/dev/null | sort | while IFS= read -r file; do
                    plan_file "$file" "${file#"$from"/}"
                done
            fi
            if [ -d "$from/1_drafts" ]; then
                find "$from/1_drafts" -type f -name '*.md' 2>/dev/null | sort | while IFS= read -r file; do
                    record skipped "${file#"$from"/}" "" "legacy drafts are not migrated"
                done
            fi
            ;;
        intelligence)
            if [ -d "$from/3_intelligences" ]; then
                find "$from/3_intelligences" -type f -name '*.md' 2>/dev/null | sort | while IFS= read -r file; do
                    plan_file "$file" "${file#"$from"/}"
                done
            fi
            ;;
        agents-md)
            if [ -f "$from/AGENTS.md" ]; then
                old_rel="AGENTS.md"
                new_rel="3_intelligence/agent/legacy-agents.md"
                record mapped "$old_rel" "$new_rel" "legacy root AGENTS.md preserved as reviewable agent material"
                printf '%s\t%s\t%s\n' "$from/AGENTS.md" "$old_rel" "$new_rel" >> "$plan_tmp"
                printf '%s\t%s\n' "$old_rel" "$new_rel" >> "$map_tmp"
            fi
            ;;
        *)
            printf 'Unknown migration section: %s\n' "$selected" >&2
            exit 2
            ;;
    esac
}

if [ "$all" = true ]; then
    for part in config knowledge intelligence agents-md; do
        plan_section "$part"
    done
    section_name=all
else
    plan_section "$section"
    section_name=$section
fi

if awk -F '\t' '{ print $3 }' "$plan_tmp" | sort | uniq -d | grep . >/dev/null 2>&1; then
    awk -F '\t' '{ print $3 }' "$plan_tmp" | sort | uniq -d | while IFS= read -r target; do
        record warning "" "$target" "lowercase target path collision"
    done
    if [ "$json" = true ]; then
        printf '{"ok":false,"error":"target_path_collision"}\n'
    else
        printf 'Migration blocked: target path collision\n' >&2
    fi
    exit 1
fi

rel_link_from() {
    local from_rel=$1
    local to_rel=$2
    local from_dir
    from_dir=$(dirname "$from_rel")
    awk -v from_dir="$from_dir" -v to_rel="$to_rel" '
    BEGIN {
      if (from_dir == "." || from_dir == "") {
        print to_rel
        exit
      }
      nf = split(from_dir, f, "/")
      nt = split(to_rel, t, "/")
      i = 1
      while (i <= nf && i <= nt && f[i] == t[i]) i++
      out = ""
      for (j = i; j <= nf; j++) out = out "../"
      for (j = i; j <= nt; j++) {
        out = out t[j]
        if (j < nt) out = out "/"
      }
      if (out == "") out = "."
      print out
    }'
}

rewrite_links() {
    local old_abs=$1
    local old_rel=$2
    local new_rel=$3
    local out=$4
    awk -v old_root="$from" -v old_rel="$old_rel" -v new_rel="$new_rel" -v map_file="$map_tmp" '
    BEGIN {
      while ((getline line < map_file) > 0) {
        split(line, parts, "\t")
        old_path = parts[1]
        new_path = parts[2]
        map[old_path] = new_path
        base = old_path
        sub(/^.*\//, "", base)
        sub(/\.md$/, "", base)
        key = tolower(base)
        gsub(/[ _]+/, "-", key)
        if (wiki[key] == "") wiki[key] = new_path
        else wiki[key] = "__AMBIGUOUS__"
      }
      close(map_file)
    }
    {
      line = $0
      for (old_path in map) {
        abs = old_root "/" old_path
        if (index(line, abs) > 0) {
          gsub(abs, "__STRATA_LINK__" map[old_path], line)
          printf "rewritten\t%s\t%s\tabsolute path rewritten\n", old_rel, map[old_path] >> "/dev/stderr"
        }
      }
      while (match(line, /\[\[[^]]+\]\]/)) {
        token = substr(line, RSTART, RLENGTH)
        label = token
        gsub(/^\[\[|\]\]$/, "", label)
        key = tolower(label)
        gsub(/[ _]+/, "-", key)
        replacement = ""
        if (wiki[key] == "__AMBIGUOUS__") {
          printf "warning\t%s\t\tambiguous wikilink: %s\n", old_rel, label >> "/dev/stderr"
          replacement = label
        } else if (wiki[key] != "") {
          replacement = "[" label "](__STRATA_LINK__" wiki[key] ")"
          printf "rewritten\t%s\t%s\twikilink rewritten: %s\n", old_rel, wiki[key], label >> "/dev/stderr"
        } else {
          printf "warning\t%s\t\tunresolved wikilink: %s\n", old_rel, label >> "/dev/stderr"
          replacement = label
        }
        line = substr(line, 1, RSTART - 1) replacement substr(line, RSTART + RLENGTH)
      }
      print line
    }' "$old_abs" 2>> "$records_tmp.raw" > "$out.raw"

    cp "$out.raw" "$out"
    while IFS="$(printf '\t')" read -r kind source target detail; do
        [ -n "$kind" ] || continue
        record "$kind" "$source" "$target" "$detail"
    done < "$records_tmp.raw"
    rm -f "$records_tmp.raw" "$out.raw"

    # Convert placeholder target-relative links after awk has identified targets.
    while grep -F '__STRATA_LINK__' "$out" >/dev/null 2>&1; do
        placeholder=$(sed -n 's/^.*__STRATA_LINK__\([^])" ]*\).*$/\1/p' "$out" | sed -n '1p')
        [ -n "$placeholder" ] || break
        relative=$(rel_link_from "$new_rel" "$placeholder")
        sed "s#__STRATA_LINK__${placeholder}#${relative}#g" "$out" > "$out.next"
        mv "$out.next" "$out"
    done
}

legacy_entity_display_value() {
    local old_rel=$1
    awk -v rel="$old_rel" '
    BEGIN {
      n = split(rel, parts, "/")
      for (i = 1; i <= n; i++) lower[i] = tolower(parts[i])
      for (i = 1; i <= n; i++) {
        if (lower[i] == "stocks" || lower[i] == "cryptocurrencies" || lower[i] == "cryptos" || lower[i] == "companies") {
          if (i + 1 <= n) print parts[i + 1]
          exit
        }
      }
    }'
}

legacy_entity_display_key() {
    local old_rel=$1
    awk -v rel="$old_rel" '
    BEGIN {
      n = split(rel, parts, "/")
      for (i = 1; i <= n; i++) {
        bucket = tolower(parts[i])
        if (bucket == "stocks") { print "ticker"; exit }
        if (bucket == "cryptocurrencies" || bucket == "cryptos") { print "symbol"; exit }
        if (bucket == "companies") { print "display_name"; exit }
      }
    }'
}

content_has_frontmatter_key() {
    local file=$1
    local key=$2
    awk -v key="$key" '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---" { exit }
    in_fm && index($0, key ":") == 1 { found = 1; exit }
    END { exit found ? 0 : 1 }
    ' "$file"
}

inject_display_metadata() {
    local content=$1
    local old_rel=$2
    local new_rel=$3
    local key
    local value
    local tmp

    case "$new_rel" in
        2_knowledge/entity/company/*|2_knowledge/entity/stock/*|2_knowledge/entity/cryptocurrency/*) ;;
        *) return 0 ;;
    esac

    key=$(legacy_entity_display_key "$old_rel")
    value=$(legacy_entity_display_value "$old_rel")
    [ -n "$key" ] || return 0
    [ -n "$value" ] || return 0

    if content_has_frontmatter_key "$content" "$key"; then
        return 0
    fi

    tmp="${content}.metadata"
    if awk 'NR == 1 && $0 == "---" { found = 1 } END { exit found ? 0 : 1 }' "$content"; then
        awk -v key="$key" -v value="$value" '
        NR == 1 && $0 == "---" {
          print
          printf "%s: \"%s\"\n", key, value
          next
        }
        { print }
        ' "$content" > "$tmp"
    else
        {
            printf '%s\n' '---'
            printf '%s: "%s"\n' "$key" "$value"
            printf '%s\n' '---'
            sed -n '1,$p' "$content"
        } > "$tmp"
    fi
    mv "$tmp" "$content"
    record metadata "$old_rel" "$new_rel" "${key} preserved as ${value}"
}

candidate_count=0
existing_count=0
written_count=0

while IFS="$(printf '\t')" read -r old_abs old_rel new_rel; do
    [ -n "$old_abs" ] || continue
    candidate_count=$((candidate_count + 1))
    content="$content_dir/$candidate_count"
    rewrite_links "$old_abs" "$old_rel" "$new_rel" "$content"
    inject_display_metadata "$content" "$old_rel" "$new_rel"

    target="$to/$new_rel"
    if [ -f "$target" ]; then
        if cmp -s "$content" "$target"; then
            existing_count=$((existing_count + 1))
            record existing "$old_rel" "$new_rel" "target already matches migrated content"
            continue
        fi
        record warning "$old_rel" "$new_rel" "target exists with different content"
        if [ "$json" = true ]; then
            printf '{"ok":false,"error":"target_exists","target":'
            strata_json_string "$new_rel"
            printf '}\n'
        else
            printf 'Migration blocked: target exists with different content: %s\n' "$new_rel" >&2
        fi
        exit 1
    fi

    mkdir -p "$(dirname "$target")"
    cp "$content" "$target"
    written_count=$((written_count + 1))
    record written "$old_rel" "$new_rel" "migrated"
    if [ -x "$to/0_core/script/index.sh" ]; then
        "$to/0_core/script/index.sh" --vault "$to" --target "$target" >/dev/null 2>&1 || record warning "$old_rel" "$new_rel" "indexing failed"
    fi
done < "$plan_tmp"

generated_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
report_path="$report_dir/migration-${section_name}-$(date -u '+%Y-%m-%dT%H%M%SZ').json"

mapped_count=$(awk -F '\t' '$1 == "mapped" { count++ } END { print count + 0 }' "$records_tmp")
unmapped_count=$(awk -F '\t' '$1 == "unmapped" { count++ } END { print count + 0 }' "$records_tmp")
skipped_count=$(awk -F '\t' '$1 == "skipped" { count++ } END { print count + 0 }' "$records_tmp")
rewritten_count=$(awk -F '\t' '$1 == "rewritten" { count++ } END { print count + 0 }' "$records_tmp")
warning_count=$(awk -F '\t' '$1 == "warning" { count++ } END { print count + 0 }' "$records_tmp")
metadata_count=$(awk -F '\t' '$1 == "metadata" { count++ } END { print count + 0 }' "$records_tmp")

{
    printf '{\n'
    printf '  "ok": true,\n'
    printf '  "generated_at": '; strata_json_string "$generated_at"; printf ',\n'
    printf '  "section": '; strata_json_string "$section_name"; printf ',\n'
    printf '  "from": '; strata_json_string "$from"; printf ',\n'
    printf '  "to": '; strata_json_string "$to"; printf ',\n'
    printf '  "source_mode": "read-only",\n'
    printf '  "candidate_count": %s,\n' "$candidate_count"
    printf '  "written_count": %s,\n' "$written_count"
    printf '  "existing_count": %s,\n' "$existing_count"
    printf '  "mapped_count": %s,\n' "$mapped_count"
    printf '  "unmapped_count": %s,\n' "$unmapped_count"
    printf '  "skipped_count": %s,\n' "$skipped_count"
    printf '  "rewritten_count": %s,\n' "$rewritten_count"
    printf '  "metadata_count": %s,\n' "$metadata_count"
    printf '  "warning_count": %s,\n' "$warning_count"
    printf '  "records": [\n'
    first=true
    while IFS="$(printf '\t')" read -r kind old_rel new_rel detail; do
        [ -n "$kind" ] || continue
        if [ "$first" = true ]; then first=false; else printf ',\n'; fi
        printf '    {"kind":'; strata_json_string "$kind"
        printf ',"old_path":'; strata_json_string "$old_rel"
        printf ',"new_path":'; strata_json_string "$new_rel"
        printf ',"detail":'; strata_json_string "$detail"
        printf '}'
    done < "$records_tmp"
    printf '\n  ]\n'
    printf '}\n'
} > "$report_path"

if [ "$json" = true ]; then
    printf '{"ok":true,"section":'
    strata_json_string "$section_name"
    printf ',"report":'
    strata_json_string "$(strata_rel_path "$report_path" "$to")"
    printf ',"written_count":%s,"existing_count":%s,"skipped_count":%s,"warning_count":%s}\n' \
        "$written_count" "$existing_count" "$skipped_count" "$warning_count"
else
    printf 'Migration %s complete: %s written, %s existing, %s skipped, %s warnings\n' \
        "$section_name" "$written_count" "$existing_count" "$skipped_count" "$warning_count"
    printf 'Report: %s\n' "$(strata_rel_path "$report_path" "$to")"
fi
