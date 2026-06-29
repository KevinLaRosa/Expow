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
    while read -r name w_path ios_id ios_orig; do
        if [[ -n "$name" && "$name" != "null" && ! -d "$w_path" ]]; then
            echo -e "\033[1;33mNettoyage de la cible périmée pour : $name\033[0m"
            if [[ -n "$ios_id" && "$ios_id" != "null" ]]; then
                xcrun simctl rename "$ios_id" "$ios_orig" 2>/dev/null || true
            fi
            stale_keys+=("$name")
        fi
    done < <(jq -r 'to_entries[]? | "\(.key) \(.value.path) \(.value.ios.id) \(.value.ios.originalName)"' "$TARGETS_FILE")

    for key in "${stale_keys[@]}"; do
        jq "del(.\"$key\")" "$TARGETS_FILE" > "$TARGETS_FILE.tmp" && mv "$TARGETS_FILE.tmp" "$TARGETS_FILE"
    done
}

allocate_targets() {
    local wt_name="$1"
    local wt_path="$2"
    
    clean_stale_targets
    
    local existing=$(jq -r ".\"$wt_name\" // empty" "$TARGETS_FILE")
    if [[ -n "$existing" ]]; then
        return 0
    fi
    
    # 1. Allocation iOS
    local allocated_ios_udids=$(jq -r '.[].ios.id // empty' "$TARGETS_FILE" | tr '\n' ' ')
    local devices_json=$(xcrun simctl list devices available -j)
    
    local ios_udid=""
    local ios_orig=""
    
    local prefs=("iPhone 16 Pro" "iPhone 16" "iPhone 15 Pro" "iPhone 15")
    for pref in "${prefs[@]}"; do
        local found_udid=$(echo "$devices_json" | jq -r --arg name "$pref" --arg alloc "$allocated_ios_udids" '
            .devices[] | .[] | select(.name == $name) | select(.udid as $u | ($alloc | contains($u) | not)) | .udid
        ' | head -n 1)
        
        if [[ -n "$found_udid" && "$found_udid" != "null" ]]; then
            ios_udid="$found_udid"
            ios_orig="$pref"
            break
        fi
    done
    
    if [[ -z "$ios_udid" || "$ios_udid" == "null" ]]; then
        ios_udid=$(echo "$devices_json" | jq -r --arg alloc "$allocated_ios_udids" '
            .devices[] | .[] | select(.name | test("iPhone")) | select(.udid as $u | ($alloc | contains($u) | not)) | .udid
        ' | head -n 1)
        ios_orig=$(echo "$devices_json" | jq -r --arg udid "$ios_udid" '
            .devices[] | .[] | select(.udid == $udid) | .name
        ' | head -n 1)
    fi
    
    if [[ -z "$ios_udid" || "$ios_udid" == "null" ]]; then
        echo -e "\033[1;31mErreur: Aucun simulateur iOS disponible.\033[0m"
        exit 1
    fi
    
    local ios_name="$ios_orig ($wt_name)"
    xcrun simctl rename "$ios_udid" "$ios_name"
    
    # 2. Allocation Android
    local allocated_avds=$(jq -r '.[].android.originalName // empty' "$TARGETS_FILE")
    local avds=$(emulator -list-avds)
    
    local android_orig=""
    for avd in $avds; do
        if ! echo "$allocated_avds" | grep -q "^${avd}$"; then
            android_orig="$avd"
            break
        fi
    done
    
    if [[ -z "$android_orig" ]]; then
        echo -e "\033[1;31mErreur: Aucun émulateur Android (AVD) libre.\033[0m"
        exit 1
    fi
    
    # Save both
    jq --arg k "$wt_name" --arg path "$wt_path" \
       --arg ios_id "$ios_udid" --arg ios_orig "$ios_orig" --arg ios_name "$ios_name" \
       --arg android_orig "$android_orig" \
       '.[$k] = {
           path: $path, 
           ios: {id: $ios_id, originalName: $ios_orig, name: $ios_name}, 
           android: {id: "", originalName: $android_orig, name: $android_orig}
       }' "$TARGETS_FILE" > "$TARGETS_FILE.tmp" && mv "$TARGETS_FILE.tmp" "$TARGETS_FILE"
       
    echo -e "\033[1;36mCibles allouées pour $wt_name :\033[0m"
    echo -e " - iOS     : $ios_name"
    echo -e " - Android : $android_orig"
}
