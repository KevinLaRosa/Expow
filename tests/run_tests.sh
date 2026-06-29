#!/usr/bin/env bash
set -e

echo -e "\033[1;34m[TEST] Démarrage de la suite de tests unitaires pour Expow\033[0m"

# 1. Création d'un environnement sandbox sécurisé
# On isole tout dans /tmp pour ne JAMAIS toucher la vraie config de l'utilisateur
TEST_DIR="/tmp/expow_test_env"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR/bin"
mkdir -p "$TEST_DIR/.config/expow"

# 2. Redirection du HOME pour que expow lise nos faux fichiers
export HOME="$TEST_DIR"
export EXPOW_DIR="$(pwd)"
# On injecte nos faux binaires en priorité dans le PATH
export PATH="$TEST_DIR/bin:$PATH"

# 3. Création des Mocks (faux binaires pour faire croire au système qu'on a des simulateurs)
cat <<'EOF' > "$TEST_DIR/bin/xcrun"
#!/bin/bash
if [[ "$*" == *"simctl list devices"* ]]; then
    # Simuler un iPhone 16 Pro libre
    echo '{"devices":{"iOS 17.0":[{"udid":"MOCK-UUID-1234","name":"iPhone 16 Pro","state":"Shutdown"}]}}'
else
    echo "Mock xcrun $*"
fi
EOF
chmod +x "$TEST_DIR/bin/xcrun"

cat <<'EOF' > "$TEST_DIR/bin/emulator"
#!/bin/bash
if [[ "$*" == *"-list-avds"* ]]; then
    echo -e "Pixel_Mock_API_34\nPixel_Mock_API_33"
else
    echo "Mock emulator $*"
fi
EOF
chmod +x "$TEST_DIR/bin/emulator"

cat <<'EOF' > "$TEST_DIR/bin/adb"
#!/bin/bash
echo "Mock adb $*"
EOF
chmod +x "$TEST_DIR/bin/adb"

echo -e "\033[1;32m[OK] Environnement mocké prêt dans $TEST_DIR\033[0m"

# 4. Tests unitaires

echo -e "\n--- Test 1: Hashing de port (ports.sh) ---"
source "$EXPOW_DIR/lib/ports.sh"
port_1=$(get_ports "mon_repo_agent-1" | awk '{print $1}')
port_2=$(get_ports "mon_repo_agent-1" | awk '{print $1}')
port_3=$(get_ports "autre_repo_agent-1" | awk '{print $1}')

if [[ "$port_1" == "$port_2" ]]; then
    echo -e "\033[1;32m[OK] Le hash est bien déterministe pour une même clé\033[0m"
else
    echo -e "\033[1;31m[FAIL] Le hash a changé: $port_1 vs $port_2\033[0m"
    exit 1
fi

if [[ "$port_1" != "$port_3" ]]; then
    echo -e "\033[1;32m[OK] Deux repos différents ont des ports différents\033[0m"
else
    echo -e "\033[1;31m[FAIL] Collision détectée entre deux repos\033[0m"
    exit 1
fi

echo -e "\n--- Test 2: Allocation cible JSON (targets.sh) ---"
source "$EXPOW_DIR/lib/targets.sh"

init_targets
allocate_targets "mon_repo_agent-1" "/fake/path" "both" >/dev/null

ios_id=$(jq -r '."mon_repo_agent-1".ios.id' "$HOME/.config/expow/targets.json")
android_orig=$(jq -r '."mon_repo_agent-1".android.originalName' "$HOME/.config/expow/targets.json")

if [[ "$ios_id" == "MOCK-UUID-1234" ]]; then
    echo -e "\033[1;32m[OK] L'iPhone simulé a bien été réservé\033[0m"
else
    echo -e "\033[1;31m[FAIL] Problème d'allocation iOS\033[0m"
    exit 1
fi

if [[ "$android_orig" == "Pixel_Mock_API_34" ]]; then
    echo -e "\033[1;32m[OK] Le Pixel simulé a bien été réservé\033[0m"
else
    echo -e "\033[1;31m[FAIL] Problème d'allocation Android\033[0m"
    exit 1
fi

echo -e "\n--- Test 3: Verrou de concurrence (targets.lock) ---"
acquire_lock
if [[ -d "$HOME/.config/expow/targets.lock" ]]; then
    echo -e "\033[1;32m[OK] Le dossier de lock a bien été créé atomiquement\033[0m"
else
    echo -e "\033[1;31m[FAIL] Le lock n'a pas été créé\033[0m"
    exit 1
fi
release_lock
if [[ ! -d "$HOME/.config/expow/targets.lock" ]]; then
    echo -e "\033[1;32m[OK] Le verrou est bien relâché\033[0m"
else
    echo -e "\033[1;31m[FAIL] Le lock est resté coincé\033[0m"
    exit 1
fi

echo -e "\n\033[1;32m🎉 TOUS LES TESTS SONT PASSÉS AVEC SUCCÈS ! L'outil est stable.\033[0m"
