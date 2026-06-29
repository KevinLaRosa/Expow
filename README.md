# 🚀 Expow (Expo Worktree)

**Expow** is a lightweight, zero-dependency bash CLI designed for complex React Native / Expo monorepos. 

It allows AI agents or developers to work on multiple isolated environments in parallel without running into Metro port conflicts or iOS/Android emulator collisions. 

By leveraging `git worktree`, deterministic port hashing, and dynamic device allocation, **Expow** creates fully independent workspaces in seconds.

### ✨ Features
- **Git Worktree integration:** Clone isolated environments without duplicating `.git`.
- **Zero Collision:** Automatically assigns a unique Metro port and Backend port based on the worktree name.
- **Smart Device Allocation:** Locks and boots a dedicated iOS Simulator or Android Emulator per workspace.
- **Zero Dependencies:** Written purely in bash/zsh, leveraging built-in tools (`xcrun`, `adb`).

### 📦 Usage
1. `expow new <name> [--platform ios|android]`
2. `cd ~/worktrees/<repo>/<name>`
3. `expowgo` (or `expow prepare`)
4. When done: `expow rm <name>`
