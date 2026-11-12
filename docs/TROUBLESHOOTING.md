# Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| “Sign in with your provider CLI first.” | `claude auth status` reports `loggedIn: false` | Run `claude auth login` in Terminal, then click ↻ next to Agent. |
| “Install a supported coding agent to run a real repair.” | `claude` isn't on Patchbeam's search path (`~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, `/bin`) | Install Claude Code, or symlink it into one of those folders. DemoAgent keeps working either way. |
| “Choose a folder containing a Git repository.” | The folder isn't inside a Git work tree | Choose the repository root (or any folder inside it). Patchbeam won't run `git init`. |
| “This repository has no commits yet…” | Unborn `HEAD` | Make a first commit. |
| “Your uncommitted edits are not in this repair worktree.” | Working tree is dirty | Expected. The repair starts from `HEAD`. Commit first if the agent needs those edits. |
| “Shell features like “\|” aren't supported.” | The check contains shell syntax | Enter one program and its arguments, or wrap the steps in a script in your repo and run that. |
| “Couldn't find “pytest” on Patchbeam's PATH.” | Tool installed elsewhere (pyenv, nvm…) | Use an absolute path such as `/Users/you/.pyenv/shims/pytest`, or `python3 -m pytest`. |
| Check passes in Terminal but is “inconclusive” here | It exited 0 but reported no tests, or it modified tracked files | Point it at the right tests. Make sure it doesn't write into tracked files. |
| “Your branch has changed; automatic apply is paused.” | You committed or switched branches after the repair started | Open the worktree (⋯ → Reveal) and merge manually, or start a new repair. |
| “Your uncommitted edits touch the same files…” | Dirty files overlap the patch | Commit or stash those edits yourself, then Apply. |
| Panel isn't visible | Hidden via the menu bar item, or preferred display unplugged | Menu bar item → uncheck **Hide Notch Panel**, or **Reset Panel Layout**. |
| ⌃⌥Space does nothing | Another app owns the shortcut | Settings → General shows the conflict. Use the menu bar item → New Repair. |
| “Patchbeam can't be opened because Apple cannot check it…” | Unsigned preview DMG | Control-click → Open → Open, or build from source. Don't disable Gatekeeper. |
| Leftover `patchbeam/*` branches or worktrees | App quit mid-run | The capsule shows “Interrupted — worktree preserved.” Use ⋯ → Discard Worktree, or `git worktree list` and `git worktree remove <path>` yourself. |
