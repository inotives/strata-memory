#!/usr/bin/env bash

strata_rel_path() {
    local path=$1
    local vault=$2

    case "$path" in
        "$vault"/*) printf '%s\n' "${path#"$vault"/}" ;;
        *) printf '%s\n' "$path" ;;
    esac
}

strata_detect_strata() {
    case "$1" in
        0_core/*) printf '%s\n' "0_core" ;;
        1_draft/*) printf '%s\n' "1_draft" ;;
        2_knowledge/*) printf '%s\n' "2_knowledge" ;;
        3_intelligence/*) printf '%s\n' "3_intelligence" ;;
        *) return 1 ;;
    esac
}

strata_default_status() {
    local strata=$1
    local rel=$2

    case "$rel" in
        */_archived/*|*_archived/*) printf '%s\n' "archived"; return 0 ;;
    esac

    case "$strata" in
        0_core) printf '%s\n' "core" ;;
        1_draft) printf '%s\n' "pending" ;;
        2_knowledge|3_intelligence) printf '%s\n' "verified" ;;
        *) return 1 ;;
    esac
}

strata_make_id() {
    local rel=$1
    local stamp
    local sum

    stamp=$(date -u '+%Y%m%d_%H%M%S')
    sum=$(printf '%s' "$rel" | cksum | awk '{print $1}')
    printf 'mem_%s_%s\n' "$stamp" "$sum"
}

strata_extract_scalar() {
    local file=$1
    local key=$2

    awk -v key="$key" '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---" { exit }
    in_fm {
      prefix = key ":"
      if (index($0, prefix) == 1) {
        value = substr($0, length(prefix) + 1)
        sub(/^[ \t]*/, "", value)
        sub(/[ \t]*$/, "", value)
        if (value ~ /^".*"$/) {
          value = substr(value, 2, length(value) - 2)
        }
        print value
        exit
      }
    }
    ' "$file"
}

strata_extract_array_block() {
    local file=$1
    local key=$2

    awk -v key="$key" '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---" { exit }
    in_fm {
      prefix = key ":"
      if (index($0, prefix) == 1) {
        found = 1
        print $0
        next
      }
      if (found) {
        if ($0 ~ /^[ ][ ]-/ || $0 ~ /^\t-/ || $0 ~ /^[ \t]*$/) {
          print $0
          next
        }
        exit
      }
    }
    ' "$file"
}

strata_extract_body() {
    local file=$1

    awk '
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---" { in_fm = 0; body = 1; next }
    !in_fm { print }
    NR == 1 && $0 != "---" { body = 1 }
    ' "$file"
}

strata_extract_array_json() {
    local file=$1
    local key=$2

    awk -v key="$key" '
    function trim(s) {
      sub(/^[ \t]*/, "", s)
      sub(/[ \t]*$/, "", s)
      return s
    }
    function emit_value(v) {
      v = trim(v)
      if (v ~ /^".*"$/) {
        v = substr(v, 2, length(v) - 2)
      }
      gsub(/\\/,"\\\\",v)
      gsub(/"/,"\\\"",v)
      if (count > 0) {
        printf ","
      }
      printf "\"%s\"", v
      count++
    }
    NR == 1 && $0 == "---" { in_fm = 1; next }
    in_fm && $0 == "---" { exit }
    in_fm {
      prefix = key ":"
      if (index($0, prefix) == 1) {
        found = 1
        next
      }
      if (found) {
        if ($0 ~ /^[ ][ ]-/ || $0 ~ /^\t-/) {
          line = $0
          sub(/^[ \t]*-[ \t]*/, "", line)
          emit_value(line)
          next
        }
        if ($0 ~ /^[ \t]*$/) {
          next
        }
        exit
      }
    }
    END {
      printf "\n"
    }
    ' "$file" | awk '{ printf "[%s]", $0 }'
}
