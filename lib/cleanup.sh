#!/usr/bin/env bash
set -euo pipefail

source "$EXPOW_DIR/lib/ports.sh"
source "$EXPOW_DIR/lib/targets.sh"

cmd="${1:-}"

if [[ "$cmd" == "list" ]]; then
    init_targets
    clean_stale_targets
    echo -e "\033[1;34mWorktrees actifs :\033[0m"
    jq -r 'to_entries[] | " - \(.key):\n    iOS: \(.value.ios.name)\n    Android: \(.value.android.originalName)"' "$TARGETS_FILE"
    exit 0
fi

if [[ "$cmd" == "rm" ]]; then
    WT_NAME="${2:-}"
    if [[ -z "$WT_NAME" ]]; then
        echo -e "\033[1;31mNom du worktree à supprimer requis.\033[0m"
        exit 1
    fi
    
    REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null 2>&1)
    if [[ -z "$REPO_ROOT" ]]; then
        echo -e "\033[1;31mErreur: Pas dans un dépôt git. Placez-vous dans le dépôt pour supprimer un worktree.\033[0m"
        exit 1
    fi
    GIT_COMMON_DIR=$(git rev-parse --git-common-dir 2>/dev/null)
    REAL_REPO_ROOT=$(cd "$GIT_COMMON_DIR/.." && pwd)
    REPO_NAME=$(basename "$REAL_REPO_ROOT")
    UNIQUE_ID="${REPO_NAME}_${WT_NAME}"
    
    init_targets
    
    wt_path=$(jq -r ".\"$UNIQUE_ID\".path // empty" "$TARGETS_FILE")
    if [[ -z "$wt_path" ]]; then
        wt_path=$(git worktree list | grep "/$WT_NAME " | awk '{print $1}' || true)
    fi
    
    if [[ -z "$wt_path" && $(jq -r "has(\"$UNIQUE_ID\")" "$TARGETS_FILE") == "false" ]]; then
        echo -e "\033[1;31mRien à nettoyer. Le worktree ou la cible $WT_NAME est introuvable.\033[0m"
        exit 0
    fi
    
    ios_id=$(jq -r ".\"$UNIQUE_ID\".ios.id // empty" "$TARGETS_FILE")
    ios_orig=$(jq -r ".\"$UNIQUE_ID\".ios.originalName // empty" "$TARGETS_FILE")
    if [[ -n "$ios_id" && "$ios_id" != "null" ]]; then
        echo -e "\033[1;33mRestauration du nom du simulateur iOS...\033[0m"
        xcrun simctl rename "$ios_id" "$ios_orig" 2>/dev/null || true
    fi
    
    android_id=$(jq -r ".\"$UNIQUE_ID\".android.id // empty" "$TARGETS_FILE")
    
    jq "del(.\"$UNIQUE_ID\")" "$TARGETS_FILE" > "$TARGETS_FILE.tmp" && mv "$TARGETS_FILE.tmp" "$TARGETS_FILE"
    
    ports=$(get_ports "$UNIQUE_ID")
    backend_port=$(echo "$ports" | awk '{print $1}')
    metro_port=$(echo "$ports" | awk '{print $2}')
    
    if [[ -n "$android_id" && "$android_id" != "null" ]]; then
        echo -e "\033[1;33mNettoyage des reverse ports ADB...\033[0m"
        adb -s "$android_id" reverse --remove tcp:$metro_port 2>/dev/null || true
        adb -s "$android_id" reverse --remove tcp:$backend_port 2>/dev/null || true
    fi
    
    if lsof -Pi :$metro_port -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo -e "\033[1;33mArrêt du processus utilisant le port Metro $metro_port...\033[0m"
        kill -9 $(lsof -Pi :$metro_port -sTCP:LISTEN -t) || true
    fi
    
    if [[ -n "$wt_path" ]]; then
        if [[ "$wt_path" == "$REAL_REPO_ROOT" ]]; then
            echo -e "\033[1;34mDépôt principal détecté. Suppression de la réservation sans effacer les fichiers.\033[0m"
        else
            echo -e "\033[1;34mSuppression du worktree git...\033[0m"
            if cd "$wt_path" 2>/dev/null; then
                main_repo=$(git rev-parse --git-common-dir)
                cd "$main_repo"
                git worktree remove -f "$wt_path"
            else
                echo -e "\033[1;33mLe dossier $wt_path est introuvable. Effectuez un 'git worktree prune' depuis votre dépôt principal si nécessaire.\033[0m"
            fi
        fi
    fi
    
    echo -e "\033[1;32mWorktree $WT_NAME supprimé avec succès.\033[0m"
    exit 0
fi
