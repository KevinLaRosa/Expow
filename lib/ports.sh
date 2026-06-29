#!/usr/bin/env bash

get_ports() {
    local name="$1"
    # Generate robust hash from name to avoid anagram collisions
    local shasum_out=$(echo -n "$name" | shasum | awk '{print $1}')
    local hex_prefix=${shasum_out:0:4}
    local hash=$(( 16#$hex_prefix % 100 ))
    local offset=$(( hash + 1 ))
    
    local backend_port=$(( 3100 + offset ))
    local metro_port=$(( 8100 + offset ))
    
    echo "$backend_port $metro_port"
}
