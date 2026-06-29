#!/usr/bin/env bash

get_ports() {
    local name="$1"
    local hash_cmd="shasum"
    if ! command -v shasum >/dev/null 2>&1 && command -v sha1sum >/dev/null 2>&1; then
        hash_cmd="sha1sum"
    fi
    local shasum_out=$(echo -n "$name" | $hash_cmd | awk '{print $1}')
    local hex_prefix=${shasum_out:0:4}
    local hash=$(( 16#$hex_prefix % 100 ))
    local offset=$(( hash + 1 ))
    
    local backend_port=$(( 3100 + offset ))
    local metro_port=$(( 8100 + offset ))
    
    echo "$backend_port $metro_port"
}
