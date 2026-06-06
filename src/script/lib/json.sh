#!/usr/bin/env bash

strata_json_escape() {
    awk '
    BEGIN { ORS = "" }
    {
      gsub(/\\/,"\\\\")
      gsub(/"/,"\\\"")
      gsub(/\t/,"\\t")
      gsub(/\r/,"\\r")
      gsub(/\n/,"\\n")
      print
    }
    '
}

strata_json_string() {
    printf '"'
    printf '%s' "$1" | strata_json_escape
    printf '"'
}
