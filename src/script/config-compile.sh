#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib/paths.sh
. "${SCRIPT_DIR}/lib/paths.sh"
# shellcheck source=lib/config.sh
. "${SCRIPT_DIR}/lib/config.sh"
# shellcheck source=lib/json.sh
. "${SCRIPT_DIR}/lib/json.sh"
# shellcheck source=lib/platform.sh
. "${SCRIPT_DIR}/lib/platform.sh"

strata_usage() {
    cat <<'USAGE'
Usage: config-compile.sh [--vault PATH] [--json]

Validate 0_core/config/configs.yaml and write 0_core/cache/config.compiled.json.
Requires full-mode dependencies: jq and yq.
USAGE
}

strata_json_help() {
    cat <<'JSON'
{"command":"config-compile.sh","args":["--vault PATH","--json"],"requires":["jq","yq"],"writes":["0_core/cache/config.compiled.json"]}
JSON
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
        --json-help)
            strata_json_help
            exit 0
            ;;
        --help|-h)
            strata_usage
            exit 0
            ;;
        *)
            printf '%s\n' "Unknown argument: $1" >&2
            strata_usage >&2
            exit 2
            ;;
    esac
done

strata_check_full_dependencies

config=$(strata_config_path)
cache=$(strata_config_cache_path)
core=$(strata_core)
tmp_dir="${core}/tmp"

if [ ! -f "$config" ]; then
    printf 'Config not found: %s\n' "$config" >&2
    exit 1
fi

mkdir -p "$(dirname "$cache")" "$tmp_dir"

raw_json=$(mktemp "${tmp_dir}/config-raw-XXXXXXXX.json")
compiled=$(mktemp "${tmp_dir}/config-compiled-XXXXXXXX.json")
err_file=$(mktemp "${tmp_dir}/config-error-XXXXXXXX.txt")
trap 'rm -f "$raw_json" "$compiled" "$err_file"' EXIT HUP INT TERM

if yq -o=json '.' "$config" > "$raw_json" 2>"$err_file"; then
    :
elif yq '.' "$config" > "$raw_json" 2>"$err_file" && jq empty "$raw_json" >/dev/null 2>&1; then
    :
else
    printf 'Unable to parse config YAML: %s\n' "$config" >&2
    sed -n '1,20p' "$err_file" >&2
    exit 1
fi

generated_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

if ! jq --arg generated_at "$generated_at" '
def fail($message): error($message);
def require($condition; $message): if $condition then empty else fail($message) end;
def unique_values: length as $count | unique | length == $count;
def lower_token: type == "string" and test("^[a-z0-9][a-z0-9_-]*$");
def room_path_ok:
  type == "string"
  and length > 0
  and (startswith("/") | not)
  and (contains("..") | not)
  and test("^[a-z0-9_*/-]+$");

. as $cfg
| ($cfg.rooms // {} | to_entries | map(
    .key as $tier
    | if (.value | type) == "array" then
        .value[] | {
          tier: $tier,
          path: .path,
          pattern: ($tier + "/" + (.path // "")),
          description: (.description // ""),
          depth: (.depth // "recursive"),
          required_files: (.required_files // []),
          allowed_status: (.allowed_status // [])
        }
      else
        empty
      end
  )) as $rooms
| ($rooms | map(.pattern)) as $patterns
| ($rooms | map(select(.tier == "2_knowledge") | .path)) as $tier2_rooms
| [
    require(($cfg | type) == "object"; "config root must be an object"),
    require(($cfg.profile | type) == "string" and ($cfg.profile | length) > 0; "profile must be a non-empty string"),
    require(($cfg.retention.archived_drafts_days | type) == "number" and $cfg.retention.archived_drafts_days >= 1; "retention.archived_drafts_days must be a positive number"),
    require(($cfg.retention.default_mode // "report") == "report"; "retention.default_mode must be report for MVP"),
    require(($cfg.tags.allowed | type) == "array" and ($cfg.tags.allowed | length) > 0; "tags.allowed must be a non-empty array"),
    require(all($cfg.tags.allowed[]; lower_token); "tags.allowed values must be lowercase tokens"),
    require(($cfg.tags.allowed | unique_values); "tags.allowed values must be unique"),
    require((($cfg.rooms["1_draft"] // null) | type) == "array"; "rooms.1_draft must be an array"),
    require((($cfg.rooms["2_knowledge"] // null) | type) == "array"; "rooms.2_knowledge must be an array"),
    require((($cfg.rooms["3_intelligence"] // null) | type) == "array"; "rooms.3_intelligence must be an array"),
    require(all($rooms[]; (.tier == "1_draft" or .tier == "2_knowledge" or .tier == "3_intelligence")); "rooms may only use tier keys 1_draft, 2_knowledge, 3_intelligence"),
    require(all($rooms[]; .path | room_path_ok); "room paths must be lowercase relative paths without .."),
    require(all($rooms[]; (.depth == "recursive" or .depth == "exact")); "room depth must be recursive or exact"),
    require(all($rooms[]; (.required_files | type) == "array"); "room required_files must be arrays"),
    require(all($rooms[]; (.allowed_status | type) == "array"); "room allowed_status must be arrays"),
    require(($patterns | unique_values); "room patterns must be unique"),
    require(($cfg.profiles | type) == "object"; "profiles must be an object"),
    require(($cfg.profiles[$cfg.profile] | type) == "object"; "active profile must exist under profiles"),
    require(all($cfg.profiles | to_entries[]; (.value.tier2_rooms | type) == "array"); "profile tier2_rooms must be arrays"),
    require(all($cfg.profiles | to_entries[]; all(.value.tier2_rooms[]; . as $room | ($tier2_rooms | index($room)))); "profile tier2_rooms must reference rooms.2_knowledge paths")
  ]
| {
    generated_at: $generated_at,
    source: "0_core/config/configs.yaml",
    profile: $cfg.profile,
    retention: $cfg.retention,
    tags: {allowed: ($cfg.tags.allowed | sort)},
    rooms: $rooms,
    profiles: $cfg.profiles
  }
' "$raw_json" > "$compiled" 2>"$err_file"; then
    printf 'Config validation failed: %s\n' "$config" >&2
    sed -n '1,20p' "$err_file" >&2
    exit 1
fi

mv "$compiled" "$cache"
rm -f "$raw_json" "$err_file"
trap - EXIT HUP INT TERM

if [ "$json" = true ]; then
    printf '{"ok":true,"cache":'
    strata_json_string "$cache"
    printf ',"profile":'
    strata_json_string "$(jq -r '.profile' "$cache")"
    printf ',"rooms":%s,"tags":%s}\n' \
        "$(jq '.rooms | length' "$cache")" \
        "$(jq '.tags.allowed | length' "$cache")"
else
    printf 'Compiled config: %s\n' "$cache"
fi
