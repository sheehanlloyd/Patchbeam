# Privacy

- **No account, no telemetry, no analytics.** Patchbeam makes no network requests of its own.
- **What leaves your Mac:** only what the coding agent *you* select sends to *its* provider, under your provider account. That's the diagnostic text you reviewed in Intake, plus whatever files the agent reads in the worktree. The scripted DemoAgent sends nothing anywhere.
- **What Patchbeam reads:** the folders you choose (never a disk scan), the clipboard only when you click **Paste**, and files you drop or choose.
- **macOS permissions requested:** none. No Accessibility, Screen Recording, Full Disk Access, microphone or camera access. The global shortcut uses the Carbon hot-key API, which needs no permission.
- **Provider credentials:** never read. Sign-in status comes from `claude auth status --json`, and only the `loggedIn` boolean is used.
- **Stored locally:** `~/Library/Application Support/Patchbeam/` holds the SQLite database (capsules, event summaries, verification records), patch files, check logs, the agent's raw stream (`agent-stream-*.jsonl`), app-owned worktrees and demo repos.
- **Deleting data:** Settings → Privacy → **Delete All Local History** removes finished capsules, logs, patches and their worktrees. To remove everything, quit Patchbeam and delete `~/Library/Application Support/Patchbeam` and the preferences domain `app.patchbeam.Patchbeam` (`defaults delete app.patchbeam.Patchbeam`). App-owned branches named `patchbeam/*` in your repositories are deleted when you discard a capsule. Any left over can be listed with `git branch --list 'patchbeam/*'`.
