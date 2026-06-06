#!/usr/bin/env bash

strata_config_path() {
    printf '%s/config/configs.yaml\n' "$(strata_core)"
}

strata_config_exists() {
    [ -f "$(strata_config_path)" ]
}

strata_config_allowed_tags() {
    awk '
    /^tags:/ { in_tags = 1; next }
    in_tags && /^[^ ]/ { in_tags = 0 }
    in_tags && /^[ ]+allowed:/ { in_allowed = 1; next }
    in_allowed && /^[ ]+-[ ]+/ {
      value = $0
      sub(/^[ ]+-[ ]+/, "", value)
      gsub(/^"|"$/, "", value)
      print value
      next
    }
    in_allowed && /^[^ ]/ { exit }
    ' "$(strata_config_path)"
}

strata_config_retention_archived_drafts_days() {
    awk '
    /^retention:/ { in_retention = 1; next }
    in_retention && /^[^ ]/ { exit }
    in_retention && /^[ ]+archived_drafts_days:/ {
      value = $0
      sub(/^.*archived_drafts_days:[ ]*/, "", value)
      gsub(/^"|"$/, "", value)
      print value
      exit
    }
    ' "$(strata_config_path)"
}

strata_config_room_patterns() {
    awk '
    /^rooms:/ { in_rooms = 1; next }
    in_rooms && /^profiles:/ { exit }
    in_rooms && /^[ ][ ][123]_/{ tier=$1; sub(/:$/, "", tier); next }
    in_rooms && /^[ ][ ][ ][ ][-][ ]path:/ {
      value = $0
      sub(/^.*path:[ ]*/, "", value)
      gsub(/^"|"$/, "", value)
      if (tier != "") print tier "/" value
    }
    ' "$(strata_config_path)"
}

strata_config_profile() {
    awk '
    /^profile:/ {
      value = $0
      sub(/^profile:[ ]*/, "", value)
      gsub(/^"|"$/, "", value)
      print value
      exit
    }
    ' "$(strata_config_path)"
}

strata_config_profile_tier2_rooms() {
    local profile=$1
    awk -v profile="$profile" '
    /^profiles:/ { in_profiles = 1; next }
    in_profiles && $0 ~ "^[ ][ ]" profile ":" { in_profile = 1; next }
    in_profile && /^[ ][ ][a-zA-Z0-9_-]+:/ && $0 !~ "^[ ][ ]" profile ":" { exit }
    in_profile && /^[ ][ ][ ][ ]tier2_rooms:/ { in_rooms = 1; next }
    in_rooms && /^[ ][ ][ ][ ][ ][ ]-[ ]+/ {
      value = $0
      sub(/^[ ]+-[ ]+/, "", value)
      gsub(/^"|"$/, "", value)
      print value
      next
    }
    in_rooms && /^[ ][ ][ ][ ][^ ]/ { exit }
    ' "$(strata_config_path)"
}
