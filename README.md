# 🚀 Expow (Expo Worktree)

<p align="center">
  <b>A lightweight, zero-dependency bash CLI for parallel and isolated React Native / Expo development.</b>
</p>

---

## 🧐 The Problem

When working on Expo / React Native projects, testing different branches or collaborating with multiple AI Agents simultaneously often leads to chaos:
- **Port Collisions:** Multiple Metro Bundlers trying to bind to port `8081`.
- **Simulator Hijacking:** Running `expo run:ios` overrides the simulator someone else (or an agent) is currently using.
- **Node Modules Hell:** Cloning the repository inside a subfolder causes Metro's `haste-map` to scan upwards, finding duplicate dependencies and crashing your build.

## ✨ The Solution: Expow

**Expow** solves all of this by creating perfectly isolated sandboxes using `git worktree`, mathematical port generation, and atomic device locking.

- **Git Worktree integration:** Clones isolated environments instantly without duplicating the heavy `.git` folder.
- **Zero Port Collisions:** Deterministically hashes the workspace name to assign a unique Metro port (e.g. `8154`) and Backend port (e.g. `3154`). No centralized state required!
- **Smart Device Allocation:** Scans your available iOS Simulators and Android Emulators, securely locks one dedicated device per workspace, and automatically boots it.
- **Multi-Agent Safe:** Employs atomic POSIX locks (`mkdir`) to ensure multiple AI agents booting exactly at the same millisecond don't race-condition the device registry.
- **Zero Dependencies:** Written purely in bash/zsh. It relies on built-in OS tools (`jq`, `awk`) and your existing mobile SDKs.
- **Cross-Platform:** Works flawlessly on macOS (iOS + Android) and natively on Linux (Android only).

---

## 📦 Installation

To get the most out of Expow, you should add its wrapper to your `~/.zshrc` or `~/.bashrc`. This allows the tool to automatically source environment variables directly into your current terminal session.

```bash
# In your ~/.zshrc

# 1. Add Expow bin to your PATH
export PATH="/path/to/expow/bin:$PATH"

# 2. Add the Auto-Source Wrapper
expow() {
  if [[ "$1" == "prepare" ]]; then
    command expow "$@" && [ -f .expow.env ] && source .expow.env
  else
    command expow "$@"
  fi
}
```

---

## 🛠 Usage Guide

### 1. Create an isolated environment
```bash
# Inside your main git repository
expow new feature-branch --platform ios
```
*This instantly creates a physical folder outside your repo, links it via `git worktree`, locks an iPhone simulator, calculates unique ports, and runs `npm install`.*

### 2. Navigate and Boot
```bash
cd ~/worktrees/my-repo/feature-branch
expow prepare
```
*This boots the dedicated iPhone, configures ADB reverse ports (if on Android), and injects the Magic Aliases into your terminal.*

### 3. Run the App (The Magic Aliases)
Instead of copy-pasting long Expo commands with specific ports and UDIDs, **Expow** generates dynamic aliases for you on the fly. Just type:
- `xstart` : Starts the Metro Bundler on your unique port.
- `xios` : Compiles and launches the app exclusively on your locked iOS Simulator.
- `xandroid` : Compiles and launches the app on your locked Android Emulator.

### 4. Teardown
```bash
# From your main repository
expow rm feature-branch
```
*This kills orphaned Metro processes on your port, releases the device lock, cleans up ADB tunnels, and safely removes the worktree.*

---

## ⚙️ Configuration (Crucial for Expo)

By default, Expow creates your worktrees **OUTSIDE** of your main repository (in `~/worktrees/`). 

> ⚠️ **Why outside?** 
> If a worktree is created inside your main repository (e.g. `./.worktrees/agent-1`), Expo's Metro Bundler will scan the parent directories, find the parent's `node_modules`, and crash massively due to `haste-map` naming collisions.

If you want to change the default base path (for example, to store worktrees on an external SSD), you can create a global configuration file:

```bash
mkdir -p ~/.config/expow
echo 'WORKTREES_BASE="/Volumes/SSD/worktrees"' > ~/.config/expow/config
```

---

## 🧠 Internal Architecture

Expow is heavily decoupled to remain completely agnostic of your project's internal scripts:

1. **`lib/ports.sh` (Stateless Hashing):** Passes `repoName_worktreeName` through a `shasum` hash function to mathematically generate collision-free ports. No database needed!
2. **`lib/targets.sh` (Atomic Registry):** Queries `xcrun simctl` and `emulator -list-avds`. Locks devices in a central `~/.config/expow/targets.json` using atomic directory locks to prevent race conditions across parallel agents.
3. **`lib/setup-workspace.sh`:** Handles `git worktree` and initial scaffolding.
4. **`lib/prepare.sh`:** Handles the heavy lifting of booting devices, setting up `adb reverse` tunnels for Android, and writing the `.expow.env` file.
5. **`lib/cleanup.sh`:** Safely kills processes via `lsof`, removes `adb reverse` rules, clears JSON locks, and performs `git worktree remove`.

---

## 🧪 Testing

Expow includes a fully sandboxed test suite to guarantee safety during development.
The tests mock the filesystem (`$HOME`), `xcrun`, `emulator`, and `adb` to run safely without ever touching your real configuration or real simulators.

To run the tests:
```bash
./tests/run_tests.sh
```

*(Note: AI Agents contributing to this repo are strictly required to add tests for any new feature or bugfix).*
