# MountSync Documentation Portal

Welcome to the MountSync documentation portal. This documentation is organized according to the **Diataxis Framework**, structured into four distinct categories based on your learning and task objectives.

---

## Documentation Navigation

```text
docs/
├── tutorials/       # Learning-oriented: Step-by-step practical guides for newcomers
├── how-to/          # Problem-oriented: Goal-focused recipes for specific tasks
├── reference/       # Information-oriented: Technical specifications and command syntax
└── explanation/     # Understanding-oriented: Architectural concepts and mental models
```

---

## 1. Tutorials (Learning-Oriented)

Tutorials guide you through practical steps to achieve a successful outcome as a newcomer.

* [Quickstart Tutorial](tutorials/quickstart.md): Install MountSync, verify prerequisites (`rclone`, `fuse3`), add your first dotfile (`~/.bashrc`), and simulate multi-machine replication.

---

## 2. How-to Guides (Problem-Oriented)

How-to guides provide step-by-step recipes to solve real-world problems and workflows.

* [Multiple Profiles Guide](how-to/profiles.md): Manage isolated vaults for separate environments (e.g. `work`, `personal`, `server`).
* [Tags & Groups Guide](how-to/tags-and-groups.md): Categorize dotfiles by structural groups (`-g`) and contextual tags (`-t`) for selective synchronization.
* [Ignore Patterns Guide](how-to/mosyignore.md): Exclude local caches, dependency directories, and build artifacts using `.mosyignore` with zero data loss.
* [Diagnostics & Auto-Remediation Guide](how-to/doctor-and-diagnostics.md): Inspect system health, mount point status, and auto-repair broken symlinks with `mosy doctor --fix`.
* [Diff & Backups Inspection Guide](how-to/diff-and-backups.md): Compare local files against cloud replicas, timestamped `.bak_*` safety backups, and alternative profiles with `mosy diff`.
* [Secret Leak Prevention Guide](how-to/secrets-prevention.md): Scan for unencrypted keys, tokens, and credentials before cloud vaulting with custom patterns in `secrets.conf`.
* [Snapshots & Recovery Guide](how-to/snapshots-and-recovery.md): Create on-demand safety snapshots, inspect history, edit configs with safety backups, rollback revisions, and purge obsolete backups.
* [Multi-Machine Synchronization Guide](how-to/multi-machine-sync.md): Replicate configurations across laptops, workstations, and remote servers using `mosy init` and `mosy pull`.
* [Cross-Platform Synchronization Guide](how-to/cross-platform-sync.md): Synchronize divergent dotfile paths across Linux, macOS, and Windows with `mosy link`.

---

## 3. Reference (Information-Oriented)

Reference manuals provide exhaustive technical descriptions of commands, flags, and configuration options.

* [CLI Reference](reference/cli.md): Exhaustive parameter reference, exit codes, and output examples for all 20 subcommands and global flags.
* [Configuration Reference](reference/configuration.md): Precedence hierarchy, environment variables, `~/.config/mosy/config` settings, and `mosy config set` usage.

---

## 4. Explanation (Understanding-Oriented)

Explanation documents clarify architecture, mental models, and design decisions.

* [Architecture & System Design](explanation/architecture.md): 4-layer indirection pipeline, FUSE caching mechanics, non-destructive backup strategy, and execution sequence diagrams.

---

## Quick Reference Summary

| Need | Recommended Document |
| :--- | :--- |
| First time using MountSync | [Quickstart Tutorial](tutorials/quickstart.md) |
| Looking up a command or flag | [CLI Reference](reference/cli.md) |
| Fixing a broken link or mount | [Diagnostics & Auto-Remediation Guide](how-to/doctor-and-diagnostics.md) |
| Managing snapshots and rollback | [Snapshots & Recovery Guide](how-to/snapshots-and-recovery.md) |
| Checking differences or backups | [Diff & Backups Inspection Guide](how-to/diff-and-backups.md) |
| Setting up a second machine | [Multi-Machine Sync Guide](how-to/multi-machine-sync.md) |
| Preventing credential leaks | [Secret Leak Prevention Guide](how-to/secrets-prevention.md) |
| Understanding system architecture | [Architecture & Design](explanation/architecture.md) |
