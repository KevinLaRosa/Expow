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
    
    init_targets
    
    wt_path=$(jq -r ".\"$WT_NAME\".path // empty" "$TARGETS_FILE")
    if [[ -z "$wt_path" ]]; then
        wt_path=$(git worktree list | grep "/$WT_NAME " | awk '{print $1}' || true)
        if [[ -z "$wt_path" ]]; then
            echo -e "\033[1;31mWorktree $WT_NAME introuvable.\033[0m"
            exit 1
        fi
    fi
    
    ios_id=$(jq -r ".\"$WT_NAME\".ios.id // empty" "$TARGETS_FILE")
    ios_orig=$(jq -r ".\"$WT_NAME\".ios.originalName // empty" "$TARGETS_FILE")
    if [[ -n "$ios_id" && "$ios_id" != "null" ]]; then
        echo -e "\033[1;33mRestauration du nom du simulateur iOS...\033[0m"
        xcrun simctl rename "$ios_id" "$ios_orig" 2>/dev/null || true
    fi
    
    jq "del(.\"$WT_NAME\")" "$TARGETS_FILE" > "$TARGETS_FILE.tmp" && mv "$TARGETS_FILE.tmp" "$TARGETS_FILE"
    
    ports=$(get_ports "$WT_NAME")
    metro_port=$(echo "$ports" | awk '{print $2}')
    if lsof -Pi :$metro_port -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo -e "\033[1;33mArrêt du processus utilisant le port Metro $metro_port...\033[0m"
        kill -9 $(lsof -Pi :$metro_port -sTCP:LISTEN -t) || true
    fi
    
    echo -e "\033[1;34mSuppression du worktree git...\033[0m"
    if cd "$wt_path" 2>/dev/null; then
        main_repo=$(git rev-parse --git-common-dir)
        cd "$main_repo"
        git worktree remove -f "$wt_path"
    else
        echo -e "\033[1;33mLe dossier $wt_path est introuvable. Effectuez un 'git worktree prune' depuis votre dépôt principal si nécessaire.\033[0m"
    fi
    
    echo -e "\033[1;32mWorktree $WT_NAME supprimé avec succès.\033[0m"
    exit 0
fi
