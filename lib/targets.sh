#!/usr/bin/env bash

TARGETS_FILE="$HOME/.config/expow/targets.json"

init_targets() {
    mkdir -p "$HOME/.config/expow"
    if [[ ! -f "$TARGETS_FILE" ]]; then
        echo "{}" > "$TARGETS_FILE"
    fi
}

clean_stale_targets() {
    local stale_keys=()
    while read -r name w_path kind id origName; do
        if [[ -n "$name" && ! -d "$w_path" ]]; then
            echo -e "\033[1;33mNettoyage de la cible périmée pour : $name\033[0m"
            if [[ "$kind" == "ios-sim" ]]; then
                xcrun simctl rename "$id" "$origName" 2>/dev/null || true
            fi
            stale_keys+=("$name")
        fi
    done < <(jq -r 'to_entries[] | "\(.key) \(.value.path) \(.value.kind) \(.value.id) \(.value.originalName)"' "$TARGETS_FILE")

    for key in "${stale_keys[@]}"; do
        jq "del(.\"$key\")" "$TARGETS_FILE" > "$TARGETS_FILE.tmp" && mv "$TARGETS_FILE.tmp" "$TARGETS_FILE"
    done
}

allocate_target() {
    local wt_name="$1"
    local wt_path="$2"
    local platform="$3"
    
    clean_stale_targets
    
    local existing=$(jq -r ".\"$wt_name\".kind // empty" "$TARGETS_FILE")
    if [[ -n "$existing" ]]; then
        return 0
    fi
    
    if [[ "$platform" == "ios" ]]; then
        local allocated_udids=$(jq -r '.[].id' "$TARGETS_FILE" | tr '\n' ' ')
        local devices_json=$(xcrun simctl list devices available -j)
        
        local chosen_udid=""
        local chosen_name=""
        
        local prefs=("iPhone 16 Pro" "iPhone 16" "iPhone 15 Pro" "iPhone 15")
        
        for pref in "${prefs[@]}"; do
            local found_udid=$(echo "$devices_json" | jq -r --arg name "$pref" --arg alloc "$allocated_udids" '
                .devices[] | .[] | select(.name == $name) | select(.udid as $u | ($alloc | contains($u) | not)) | .udid
            ' | head -n 1)
            
            if [[ -n "$found_udid" && "$found_udid" != "null" ]]; then
                chosen_udid="$found_udid"
                chosen_name="$pref"
                break
            fi
        done
        
        if [[ -z "$chosen_udid" || "$chosen_udid" == "null" ]]; then
            chosen_udid=$(echo "$devices_json" | jq -r --arg alloc "$allocated_udids" '
                .devices[] | .[] | select(.name | test("iPhone")) | select(.udid as $u | ($alloc | contains($u) | not)) | .udid
            ' | head -n 1)
            chosen_name=$(echo "$devices_json" | jq -r --arg udid "$chosen_udid" '
                .devices[] | .[] | select(.udid == $udid) | .name
            ' | head -n 1)
        fi
        
        if [[ -z "$chosen_udid" || "$chosen_udid" == "null" ]]; then
            echo -e "\033[1;31mErreur: Aucun simulateur iOS disponible.\033[0m"
            exit 1
        fi
        
        local new_name="$chosen_name ($wt_name)"
        xcrun simctl rename "$chosen_udid" "$new_name"
        
        jq --arg k "$wt_name" --arg path "$wt_path" --arg kind "ios-sim" --arg id "$chosen_udid" --arg orig "$chosen_name" --arg name "$new_name" \
           '.[$k] = {path: $path, kind: $kind, id: $id, originalName: $orig, name: $name}' "$TARGETS_FILE" > "$TARGETS_FILE.tmp" && mv "$TARGETS_FILE.tmp" "$TARGETS_FILE"
           
        echo -e "\033[1;36mCible iOS allouée: $new_name\033[0m"
        
    elif [[ "$platform" == "android" ]]; then
        local allocated_avds=$(jq -r '.[].originalName' "$TARGETS_FILE")
        local avds=$(emulator -list-avds)
        
        local chosen_avd=""
        for avd in $avds; do
            if ! echo "$allocated_avds" | grep -q "^${avd}$"; then
                chosen_avd="$avd"
                break
            fi
        done
        
        if [[ -z "$chosen_avd" ]]; then
            echo -e "\033[1;31mErreur: Aucun émulateur Android (AVD) libre.\033[0m"
            exit 1
        fi
        
        jq --arg k "$wt_name" --arg path "$wt_path" --arg kind "android-emu" --arg id "" --arg orig "$chosen_avd" --arg name "$chosen_avd" \
           '.[$k] = {path: $path, kind: $kind, id: $id, originalName: $orig, name: $name}' "$TARGETS_FILE" > "$TARGETS_FILE.tmp" && mv "$TARGETS_FILE.tmp" "$TARGETS_FILE"
           
        echo -e "\033[1;36mCible Android allouée: $chosen_avd\033[0m"
    fi
}
