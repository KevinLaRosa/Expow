#!/usr/bin/env bash
set -euo pipefail

source "$EXPOW_DIR/lib/ports.sh"
source "$EXPOW_DIR/lib/targets.sh"

PLATFORM=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --platform) PLATFORM="$2"; shift 2 ;;
        -*) echo -e "\033[1;31mOption inconnue: $1\033[0m"; exit 1 ;;
        *) shift ;;
    esac
done

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [[ -z "$REPO_ROOT" ]]; then
    echo -e "\033[1;31mErreur: Pas dans un dépôt git (ou worktree).\033[0m"
    exit 1
fi
WT_NAME=$(basename "$REPO_ROOT")

init_targets

saved_kind=$(jq -r ".\"$WT_NAME\".kind // empty" "$TARGETS_FILE")
if [[ -z "$saved_kind" && -z "$PLATFORM" ]]; then
    PLATFORM="ios"
elif [[ -z "$PLATFORM" ]]; then
    if [[ "$saved_kind" == "ios-sim" ]]; then PLATFORM="ios"; else PLATFORM="android"; fi
fi

allocate_target "$WT_NAME" "$REPO_ROOT" "$PLATFORM"

target_kind=$(jq -r ".\"$WT_NAME\".kind" "$TARGETS_FILE")
target_id=$(jq -r ".\"$WT_NAME\".id" "$TARGETS_FILE")
target_name=$(jq -r ".\"$WT_NAME\".name" "$TARGETS_FILE")

ports=$(get_ports "$WT_NAME")
backend_port=$(echo "$ports" | awk '{print $1}')
metro_port=$(echo "$ports" | awk '{print $2}')

VARIANT=""
if [[ -f .env ]]; then
    VARIANT=$(grep '^APP_VARIANT=' .env | cut -d= -f2 | tr -d '"' || true)
fi

echo -e "\033[1;34m[expow] Préparation de l'environnement pour $WT_NAME...\033[0m"

if [[ "$target_kind" == "ios-sim" ]]; then
    udid="$target_id"
    state=$(xcrun simctl list devices -j | jq -r --arg u "$udid" '.devices[].[] | select(.udid == $u) | .state')
    if [[ "$state" != "Booted" ]]; then
        echo -e "\033[1;33mDémarrage du simulateur $target_name ($udid)...\033[0m"
        xcrun simctl boot "$udid"
        xcrun simctl bootstatus "$udid"
    else
        echo -e "Simulateur $target_name déjà démarré."
    fi
    
    cat <<EOF > .expow.env
export WORKSPACE_NAME="$WT_NAME"
export METRO_PORT="$metro_port"
export BACKEND_PORT="$backend_port"
export PLATFORM="ios"
export IOS_UDID="$udid"
EOF
    if [[ -n "$VARIANT" ]]; then echo "export APP_VARIANT=\"$VARIANT\"" >> .expow.env; fi
    
    echo -e "\n\033[1;32m--- RÉCAPITULATIF IOS ---\033[0m"
    echo "Worktree : $WT_NAME"
    echo "Cible    : $target_name"
    echo "Ports    : Metro $metro_port, Backend $backend_port"
    echo "Variante : ${VARIANT:-<aucune>}"
    echo -e "\n\033[1;36mCommandes suggérées :\033[0m"
    echo "  source .expow.env"
    echo "  npx expo start --port \$METRO_PORT"
    echo "  npx expo run:ios --device \$IOS_UDID --port \$METRO_PORT"

elif [[ "$target_kind" == "android-emu" ]]; then
    orig_name=$(jq -r ".\"$WT_NAME\".originalName" "$TARGETS_FILE")
    
    running_serial=""
    for serial in $(adb devices | grep emulator | awk '{print $1}'); do
        avd_name=$(adb -s "$serial" emu avd name 2>/dev/null | head -n1 | tr -d '\r')
        if [[ "$avd_name" == "$orig_name" ]]; then
            running_serial="$serial"
            break
        fi
    done
    
    if [[ -z "$running_serial" ]]; then
        echo -e "\033[1;33mDémarrage de l'émulateur Android $orig_name...\033[0m"
        nohup emulator -avd "$orig_name" -no-snapshot-load > /dev/null 2>&1 &
        echo "Attente du démarrage de l'appareil (adb wait-for-device)..."
        adb wait-for-device
        
        for i in {1..10}; do
            sleep 2
            for serial in $(adb devices | grep emulator | awk '{print $1}'); do
                avd_name=$(adb -s "$serial" emu avd name 2>/dev/null | head -n1 | tr -d '\r')
                if [[ "$avd_name" == "$orig_name" ]]; then
                    running_serial="$serial"
                    break 2
                fi
            done
        done
    fi
    
    if [[ -z "$running_serial" ]]; then
        echo -e "\033[1;31mErreur: Impossible de déterminer le serial de l'émulateur.\033[0m"
        exit 1
    fi
    
    echo -e "Émulateur Android détecté sur : $running_serial"
    jq --arg k "$WT_NAME" --arg id "$running_serial" '.[$k].id = $id' "$TARGETS_FILE" > "$TARGETS_FILE.tmp" && mv "$TARGETS_FILE.tmp" "$TARGETS_FILE"
    
    echo -e "Configuration des reverse ports ADB..."
    adb -s "$running_serial" reverse --remove-all || true
    adb -s "$running_serial" reverse tcp:$metro_port tcp:$metro_port
    adb -s "$running_serial" reverse tcp:$backend_port tcp:$backend_port
    
    cat <<EOF > .expow.env
export WORKSPACE_NAME="$WT_NAME"
export METRO_PORT="$metro_port"
export BACKEND_PORT="$backend_port"
export PLATFORM="android"
export ANDROID_SERIAL="$running_serial"
EOF
    if [[ -n "$VARIANT" ]]; then echo "export APP_VARIANT=\"$VARIANT\"" >> .expow.env; fi

    echo -e "\n\033[1;32m--- RÉCAPITULATIF ANDROID ---\033[0m"
    echo "Worktree : $WT_NAME"
    echo "Cible    : $orig_name ($running_serial)"
    echo "Ports    : Metro $metro_port, Backend $backend_port"
    echo "Variante : ${VARIANT:-<aucune>}"
    echo -e "\n\033[1;36mCommandes suggérées :\033[0m"
    echo "  source .expow.env"
    echo "  npx expo start --port \$METRO_PORT"
    echo "  ANDROID_SERIAL=\$ANDROID_SERIAL npx expo run:android --port \$METRO_PORT"
fi
