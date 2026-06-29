#!/usr/bin/env bash
set -euo pipefail

source "$EXPOW_DIR/lib/ports.sh"
source "$EXPOW_DIR/lib/targets.sh"

WT_NAME=""
VARIANT=""
BRANCH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --variant) VARIANT="$2"; shift 2 ;;
        --branch) BRANCH="$2"; shift 2 ;;
        -*) echo -e "\033[1;31mOption inconnue: $1\033[0m"; exit 1 ;;
        *) WT_NAME="$1"; shift ;;
    esac
done

if [[ -z "$WT_NAME" ]]; then
    echo -e "\033[1;31mNom du worktree requis.\033[0m"
    exit 1
fi

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [[ -z "$REPO_ROOT" ]]; then
    echo -e "\033[1;31mErreur: Pas dans un dépôt git.\033[0m"
    exit 1
fi
REPO_NAME=$(basename "$REPO_ROOT")

PKG_MANAGER="npm"
WORKTREES_BASE="$HOME/worktrees"

CONF_FILE="$HOME/.config/expow/repos/$REPO_NAME.conf"
if [[ -f "$CONF_FILE" ]]; then
    source "$CONF_FILE"
fi

WT_PATH="$WORKTREES_BASE/$REPO_NAME/$WT_NAME"

if [[ -d "$WT_PATH" ]]; then
    echo -e "\033[1;31mLe worktree $WT_PATH existe déjà.\033[0m"
    exit 1
fi

echo -e "\033[1;34mCréation du worktree $WT_NAME dans $WT_PATH...\033[0m"
mkdir -p "$WORKTREES_BASE/$REPO_NAME"

if [[ -n "$BRANCH" ]]; then
    git worktree add -b "$WT_NAME" "$WT_PATH" "$BRANCH"
else
    git worktree add -b "$WT_NAME" "$WT_PATH"
fi

cd "$WT_PATH"

ports=$(get_ports "$WT_NAME")
backend_port=$(echo "$ports" | awk '{print $1}')
metro_port=$(echo "$ports" | awk '{print $2}')

init_targets
allocate_targets "$WT_NAME" "$WT_PATH"

cat <<EOF > .env
# Généré par expow (ne pas commiter)
EXPO_PUBLIC_WORKSPACE_NAME="$WT_NAME"
EXPO_PUBLIC_API_URL="http://localhost:$backend_port"
EOF
if [[ -n "$VARIANT" ]]; then
    echo "APP_VARIANT=\"$VARIANT\"" >> .env
fi

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
