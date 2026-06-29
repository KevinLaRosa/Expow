#!/usr/bin/env bash
set -euo pipefail

source "$EXPOW_DIR/lib/ports.sh"
source "$EXPOW_DIR/lib/targets.sh"

WT_NAME=""
BRANCH=""
PLATFORM="both"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --branch) BRANCH="$2"; shift 2 ;;
        --platform) PLATFORM="$2"; shift 2 ;;
        -*) echo -e "\033[1;31mOption inconnue: $1\033[0m"; exit 1 ;;
        *) WT_NAME="$1"; shift ;;
    esac
done

if [[ -z "$WT_NAME" ]]; then
    echo -e "\033[1;31mNom du worktree requis.\033[0m"
    exit 1
fi

if [[ "$PLATFORM" != "ios" && "$PLATFORM" != "android" && "$PLATFORM" != "both" ]]; then
    echo -e "\033[1;31mPlatform doit être ios, android ou both.\033[0m"
    exit 1
fi

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null 2>&1)
if [[ -z "$REPO_ROOT" ]]; then
    echo -e "\033[1;31mErreur: Pas dans un dépôt git.\033[0m"
    exit 1
fi
REPO_NAME=$(basename "$REPO_ROOT")

PKG_MANAGER="npm"
WORKTREES_BASE="$HOME/worktrees"

WT_PATH="$WORKTREES_BASE/$REPO_NAME/$WT_NAME"
UNIQUE_ID="${REPO_NAME}_${WT_NAME}"

CONF_FILE="$HOME/.config/expow/repos/$REPO_NAME.conf"
if [[ -f "$CONF_FILE" ]]; then
    source "$CONF_FILE"
fi

if [[ -d "$WT_PATH" ]]; then
    echo -e "\033[1;31mLe worktree $WT_PATH existe déjà.\033[0m"
    exit 1
fi

echo -e "\033[1;34m[1/3] Création du worktree Git pour $WT_NAME...\033[0m"
if git show-ref --verify --quiet "refs/heads/$WT_NAME"; then
    git worktree add "$WT_PATH" "$WT_NAME"
else
    git worktree add "$WT_PATH" -b "$WT_NAME"
fi

cd "$WT_PATH"

ports=$(get_ports "$UNIQUE_ID")
backend_port=$(echo "$ports" | awk '{print $1}')
metro_port=$(echo "$ports" | awk '{print $2}')

init_targets
allocate_targets "$UNIQUE_ID" "$WT_PATH" "$PLATFORM"

cat <<EOF > .env
# Généré par expow (ne pas commiter)
EXPO_PUBLIC_WORKSPACE_NAME="$WT_NAME"
EXPO_PUBLIC_API_URL="http://localhost:$backend_port"
EOF
echo ".env" >> .gitignore
echo ".expow.env" >> .gitignore

if [[ ! -d "node_modules" ]]; then
    echo -e "\033[1;34mInstallation des dépendances avec $PKG_MANAGER...\033[0m"
    $PKG_MANAGER install
fi

echo -e "\n\033[1;32mWorktree $WT_NAME préparé avec succès dans $WT_PATH\033[0m"
echo -e "\033[1;36mPour le démarrer (par défaut iOS) :\033[0m"
echo "cd $WT_PATH"
echo "expow prepare [--platform ios|android]"
