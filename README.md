# 🚀 Expow (Expo Worktree)

**Expow** is a lightweight, zero-dependency bash CLI designed for Expo projects.

It allows AI agents or developers to work on multiple isolated environments in parallel without running into Metro port conflicts or iOS/Android emulator collisions. 

By leveraging `git worktree`, deterministic port hashing, and dynamic device allocation, **Expow** creates fully independent workspaces in seconds.

### ✨ Features
- **Git Worktree integration:** Clone isolated environments without duplicating `.git`.
- **Zero Collision:** Automatically assigns a unique Metro port and Backend port based on the worktree name.
- **Smart Device Allocation:** Simultaneously locks and allocates BOTH a dedicated iOS Simulator and an Android Emulator per workspace.
- **Zero Dependencies:** Written purely in bash/zsh, leveraging built-in tools (`xcrun`, `adb`).

### 📦 Usage
1. `expow new <name> [--platform both|ios|android]` (Defaults to `both`)
2. `cd ~/worktrees/<repo>/<name>`
3. `expow prepare [--platform ios|android]` (Boots the chosen simulator and prepares the environment, default is iOS)
4. When done: `expow rm <name>`

> **Pro Tip:** Add this wrapper to your `.zshrc` or `.bashrc` so that `expow prepare` automatically injects the generated environment variables (like `$METRO_PORT`) directly into your current terminal session:
> ```bash
> expow() {
>   if [[ "$1" == "prepare" ]]; then
>     command expow "$@" && [ -f .expow.env ] && source .expow.env
>   else
>     command expow "$@"
>   fi
> }
> ```

### 🧠 How it works under the hood

#### 1. Creation (`expow new agent-x`)
- **Git Worktree:** Runs `git worktree add` to create an isolated physical folder linked to your main repository, bypassing the need to re-download the `.git` directory.
- **Port Hashing:** Passes the environment name (`agent-x`) through a `shasum` hash function to generate deterministic, collision-free ports (e.g. Metro on `8154`, Backend on `3154`).
- **Target Allocation:** Queries Xcode (`xcrun simctl`) AND Android (`emulator`) for available devices not currently assigned to another workspace, locks BOTH of them, and records them in `~/.config/expow/targets.json`.
- **Environment:** Generates an isolated `.env` file (for `app.config.ts` or standard Expo usage) and runs a clean `npm install`.

#### 2. Startup (`expow prepare`)
- **Device Boot:** Reads `targets.json` to identify the assigned device (e.g., iPhone 16 Pro). If it's offline, it boots it up.
- **ADB Tunneling:** If Android, it sets up an ADB reverse proxy (`adb reverse tcp:8154 tcp:8154`) so the emulator can talk to your isolated Metro server.
- **Shell Env:** Generates an `.expow.env` file containing variables like `METRO_PORT` and `IOS_UDID`, ready to be sourced by your shell (or auto-sourced via the wrapper above).
- **Execution Output:** Prints the exact copy-pasteable commands needed to start your app (e.g., `npx expo start --port $METRO_PORT`).

#### 3. Teardown (`expow rm agent-x`)
- **Unlocking:** Removes the device lock from `targets.json`, freeing the iPhone/Emulator for another agent or workspace.
- **Cleanup:** Kills any orphaned Metro processes lingering on the assigned port.
- **Worktree Removal:** Safely executes `git worktree remove` to delete the environment without touching your main repository.
