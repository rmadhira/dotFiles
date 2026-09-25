# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Personal dotfiles (vim, tmux, shell, git, taskwarrior) plus an installer for macOS and Ubuntu. It is being redesigned on the `redesign` branch. **`docs/DESIGN.md` is the source of truth**: read its Execution phases section to see which phase is current before changing anything.

Until the phase that replaces them, the old files stay as they are: `worksetup.sh` (broken: fails `bash -n` at line 23), plus `.vimrc`, `.tmux.conf`, `.bash_aliases` and `task_timew.sh` at the repo root.

## How the work is run

- Design first, then small phases, each ending with `--check`, a review of the diff, and a commit. Do not jump ahead of the current phase or widen its scope.
- The user's in-use machines (personal Mac, server A) stay read-only until the design says otherwise. Real installs are tested on fresh machines first.
- Linux machines have no Claude access. Failures come back as pasted output, so scripts must print what they are doing and fail with a clear report.

## Hard constraints

- **Never push without an explicit instruction.** No `git push`, remote branches, tags, PRs or other changes on GitHub unless the user asks for it in that message. Commit locally and say it is ready to push. If a requested push fails on credentials, stop and report it; never try other keys, tokens or credential helpers.
- **Public repo, no PII.** No names, emails, home paths (`/Users/<name>`, `/home/<name>`), hostnames, private IPs or personal aliases in any committed file, including docs. Personal data belongs in the separate private repo (`dotFiles-private`, cloned to `~/.config/dotfiles/private/`). Work data belongs in neither repo.
- **bash 3.2 compatible.** Scripts must run under macOS's `/bin/bash` 3.2: no associative arrays, `${var,,}`, `mapfile` or `readarray`. Commands whose flags differ between BSD and GNU (`sed -i`, `stat`, `readlink -f`) go through the platform functions in the design.
- **Zero dependencies.** Plain bash and git only. The user chose this over chezmoi, stow and yadm; do not propose switching.
- **Never destroy.** Anything replaced in `$HOME` is backed up first, and every action must be undoable.

## Checking scripts

There is no build step. Before committing a script:

```sh
/bin/bash tests/run.sh         # install.sh against throwaway fake home folders
/bin/bash -n <script>          # syntax, with macOS's bash 3.2
/bin/bash <script>             # run with bash 3.2, not a newer Homebrew bash
shellcheck <script>            # if installed (a personal package from phase 4)
```

`tests/run.sh` must pass before every commit that touches `install.sh` or `lib/`. It sets `HOME` to a temporary folder, so never run `install.sh` against the real home folder to test a change.

`tools/survey.sh` is a read-only machine survey. It redacts the home path and hostname, and shows SSH keys only as counts, because key file names can contain personal words. Its output still describes a real machine, so it belongs in chat, never in a committed file.
