# dotFiles: Cross-Platform Setup Design

2026-09-25 · Status: Draft for review

> This file lives in a public repo. It describes machine audits in general terms only: no personal names, emails, home paths, hostnames or IPs. The one name that appears is my GitHub account, which is public in the repo URL anyway.

## Goals and non-goals

One command sets up a new macOS or Linux machine with my daily tools and config. Re-running it on an existing machine is safe and only brings it in line with the repo.

**Goals**

- `git clone` + `./install.sh --profile <name>` on a fresh Mac (Apple silicon or Intel) or Ubuntu/Debian box gives a working vim, tmux and zsh/bash setup.
- One source of truth: the repo. Machines follow it through symlinks or includes, so `git pull` updates them.
- The basic setup works on any machine, office laptops included, with no login: the public repo clones anonymously. Personal data comes from a separate private repo, on personal machines only.
- Consolidate the configs that have drifted across my Mac and Linux machines without breaking any of them along the way.
- Profiles (personal, office) that add packages and config on top of a shared base.
- Personal settings live in the private layer, and machine-specific settings stay on the machine. The public repo must hold no PII.

**Non-goals (for now)**

- Fedora/RHEL (`dnf`) support. The design leaves room for it, but it is not built or tested.
- Managing secrets, SSH keys or GPG keys.
- Using a dotfile manager such as chezmoi, stow or yadm. The installer is hand-written with zero dependencies. See Alternatives considered.
- Neovim, or migrating off Vundle.
- Managing Python environments. conda stays outside the repo, and migrating off Anaconda is deferred (see Open questions and decisions).

## Current state

The repo and my personal Mac have drifted in both directions, and `worksetup.sh` does not run at all. This is from a read-only audit of the personal Mac (macOS 14.8.3, arm64) on 2026-09-25. All four machines were then surveyed with `tools/survey.sh` on the same day; see The machines below.

**Repo vs. this Mac, per file**

| File | State on this Mac | Which side is ahead | Plan |
| --- | --- | --- | --- |
| `.vimrc` | Regular file | Repo: has `set cursorline` and header comments that the Mac lacks | Repo version wins |
| `.tmux.conf` | Regular file | Mac: Dracula `task_timew.sh` status line enabled | Mac version wins |
| `task_timew.sh` | Hand-copied into `~/.tmux/plugins/tmux/scripts/` | Identical | Installer links it |
| `.zshrc` | Regular file, not in repo | Mac only | Split into shared, profile and local parts |
| `.zprofile` | Homebrew `shellenv` + `rbenv init` | Mac only | Shared part into repo, with guards |
| `.zshenv` | Sources `~/.cargo/env` | Mac only | Guarded, or kept local |
| `.gitconfig` | Per-folder identity through `includeIf` | Mac only | Shared settings into repo; identity list into the private layer |
| `.taskrc` | Default file | Mac only | Minimal shared version |
| `.bash_aliases` | Missing | Repo only, mostly commented-out Linux aliases | Useful lines into shared `shell/aliases.sh` or the private layer; the repo file is then removed. On Linux, the live `~/.bash_aliases` stays a local file |

**Where `.zshrc` content belongs**

- **Shared:** locale exports, `vbrc`/`sbrc`/`vtrc`, generic Taskwarrior aliases (`tstart`, `tstop`, `tann`, `tui`, `topen`).
- **Private layer:** project-specific Taskwarrior aliases, launchers for scripts in a cloud-drive folder, a mosh alias to a LAN host, ZeroTier aliases, a cross-compiler `PATH` entry.
- **Local only:** the conda setup block. It hard-codes the home path and `conda init` rewrites it.

**Tools on this Mac:** Homebrew, git, vim 9.1, tmux, glow, task, timew, tree, gh, taskwarrior-tui, taskopen, mosh and iTerm2 are installed. wget, fzf, ripgrep, jq, htop and bat are missing. Vundle and its five plugins, the atom-dark colour scheme, TPM and the Dracula tmux theme are present. The system bash is 3.2.57. Anaconda (conda 24.11, `defaults` channel, environments `base` and one project env) is installed twice: `~/anaconda3` (8.2 GB, in use) and `/opt/homebrew/anaconda3` from the Homebrew `anaconda` cask. Nothing in crontab or launch agents uses conda on this Mac.

**Bugs in `worksetup.sh`**

- `detect_os()` and `install_pkgs()` have empty bodies, which is a bash syntax error. The script fails `bash -n` at line 23.
- Error paths call `error_exit`, but only `error` is defined.
- It is apt-only, so it cannot run on a Mac.
- It re-clones the repo into `~/.vim/dotFiles` and copies files from there, so local edits and the checkout it runs from are ignored.
- `backup()` is defined but never called, and `cp -u` silently skips a newer local file.
- `.bash_aliases` is never installed.

**Why atom-dark was cloned and copied by hand.** On a fresh machine, `vim +PluginInstall +qall` loads `.vimrc` before any plugin exists. Line 60, `colorscheme atom-dark-256`, then fails with `E185: Cannot find color scheme 'atom-dark-256'`, and vim exits with status 1. Copying the file into `~/.vim/colors` first hid the error. Reproduced on 2026-09-25 with a throwaway `HOME`. With `silent! colorscheme atom-dark-256`, the headless install exits 0, installs all six plugins, and the next start loads `atom-dark-256` from the plugin. `.vimrc` already loads the colour scheme after `call vundle#end()`, so no reordering is needed.

**The machines.** Four machines take part in the rollout. Two are in use and have drifted, and two are fresh installs with nothing on them. The fresh ones are where the installer is first run for real (see Execution phases).

| | Personal Mac | Office Mac | Server A | Server B |
| --- | --- | --- | --- | --- |
| State | in use, drifted (audited above) | fresh install | in use, drifted | fresh install |
| OS | macOS 14.8.3, arm64 | macOS 26.4 | Ubuntu 22.04.5 LTS (6.8 HWE kernel), x86_64 | Ubuntu 26.04 LTS (7.0 kernel), x86_64 |
| Shell | zsh; bash 3.2.57 for scripts | zsh; bash 3.2 for scripts | bash 5.1.16 | bash 5.3.9 |
| Profile | personal | office | personal | personal (base until the private layer exists) |
| conda | Anaconda, installed twice | not reported | Miniconda (`~/miniconda3`), active (`base` in the prompt) | none |
| sudo | admin user | admin user | asks for a password | asks for a password |
| Managed (MDM) | no | yes: DEP, user approved | n/a | n/a |
| Homebrew | 6.0.18, owned by me | 7.0.4, owned by me | n/a | n/a |
| Surveyed | 2026-09-25 | 2026-09-25 (summary) | 2026-09-25 | 2026-09-25 |
| Claude access | yes | no | no | no |

**Server B survey (fresh 26.04).** git, vim, tmux, curl, wget, jq and htop come preinstalled, and so does Docker. `.bashrc` and `.profile` are the Ubuntu defaults. There is no `.gitconfig`, no SSH key, no vim or tmux setup, and no zsh. HTTPS to GitHub works. Every base tool has an apt package except taskopen and taskwarrior-tui. glow (2.1.1) is in Ubuntu's own apt, and Taskwarrior is still 2.6 (2.6.2).

**Server A survey (in use, 22.04).** Everything from the old setup is present: Vundle with its five plugins, TPM, Dracula, glow (2.1.1, with the charm.sh apt repo already configured), Taskwarrior 2.6.1, Timewarrior 1.4.3, mosh and tree. taskopen is installed outside apt, and taskwarrior-tui through `cargo`. fzf, ripgrep, jq and bat are missing. `.vimrc` has the same line count as the repo's, so it is probably the old copy. `.tmux.conf` and `.taskrc` (46 lines, customised) have drifted. `.bash_aliases` has 63 lines. There are four crontab entries, none mentioning conda directly. Two `includeIf` identities are set up, but the SSH key file names do not follow the `<account>_key` convention. Docker is installed (snap). apt versions are older than on 26.04: gh 2.4.0, fzf 0.29, vim 8.2, tmux 3.2a.

**Office Mac survey (fresh, company-managed).** macOS 26.4, enrolled in the employer's MDM (DEP, user approved). I am an admin, Homebrew 7.0.4 is installed and owned by me, and the standalone Command Line Tools provide git. iTerm2 is installed; whether by hand or through Homebrew was not recorded, and the design handles both. So the installer can run there technically. Whether the employer allows Homebrew and these tools is a policy question, not a technical one (see Open questions).

The servers are headless and use bash as their login shell (`/bin/bash`). On server A, `vbrc` edits `~/.bash_aliases`, `sbrc` sources `~/.bashrc`, and `vtrc` edits `~/.taskrc`. On the personal Mac, `vbrc` edits `~/.zshrc`. Machines without Claude access report failures as pasted reports (see Verbose output and error reports). Server A's full `--check` audit happens in phase 2. Hostnames and usernames are not recorded here; they belong in the private layer (`pii-patterns`).

## Design principles

Every later decision follows from these six rules. When a choice is unclear, the rule higher on the list wins.

1. **Never destroy.** Anything the installer replaces is moved to a timestamped backup first, never deleted. Every change can be undone with `--restore`.
2. **Look before touching.** `--check` and `--dry-run` show exactly what would change. A real run does nothing that a dry run did not print.
3. **Idempotent.** Each step checks whether it is already done. Running the installer twice, or after a failure halfway through, is harmless.
4. **Shared in the public repo, personal in the private layer, machine-specific stays local.** The public repo holds what every machine should have. Personal content goes to the private layer. Anything tied to one machine or one employer lives in local files that are never committed anywhere.
5. **Public-repo safe.** No names, emails, home paths, hostnames or private IPs in the repo. A pre-commit hook enforces this.
6. **Portable shell.** `install.sh` runs on macOS's built-in bash 3.2 and on Linux bash 5. That rules out associative arrays, `${var,,}`, `mapfile` and `readarray` everywhere, including the platform files. Commands whose flags differ between BSD and GNU (`sed -i`, `stat`, `readlink -f`) are only called through platform functions. Every test on the Mac runs with `/bin/bash install.sh` and `shellcheck`, so a newer-bash feature fails here first, not on a fresh machine.

## Repository layout

Config is grouped by tool, and profiles are thin overlays on a shared base. New machines clone to `~/dotFiles`. The repo can live anywhere, though: on this Mac it stays at `~/projects/<account-a>/dotFiles`. The installer works out its own location and writes that path into the stubs, so moving the repo later means re-running the installer.

```
dotFiles/
  install.sh                 # entry point; replaces worksetup.sh. Detects OS, sources one platform file
  lib/
    common.sh                # shared: linking, stubs, backups, check, restore, profiles, logging
    platform/macos.sh        # Homebrew; BSD command flags
    platform/debian.sh       # apt (Debian, Ubuntu); GNU command flags
    platform/fedora.sh       # later: dnf
  packages/
    common.txt               # base tools, one per line
    personal.txt             # profile extras
    office.txt
    map.txt                  # exceptions: list name, brew name, apt name (- skips)
  links.txt                  # every managed file: repo path, live path, mechanism
  addons.txt                 # git-cloned add-ons: component, repo URL, destination
  vim/vimrc                  # symlinked to ~/.vimrc
  tmux/tmux.conf             # symlinked to ~/.tmux.conf
  tmux/task_timew.sh         # symlinked into the Dracula scripts folder
  shell/
    zshrc  zprofile  zshenv  # sourced from the local ~/.zshrc etc.
    bashrc
    load.sh                  # the shell load order, shared by zshrc and bashrc
    aliases.sh               # shared by bash and zsh
    profiles/personal.sh     # generic personal extras
    profiles/office.sh       # generic work tools
  git/gitconfig              # included from the local ~/.gitconfig
  task/taskrc                # included from the local ~/.taskrc
  hooks/pre-commit           # PII guard
  tools/survey.sh            # standalone read-only machine survey (phase 0; replaced by --report)
  docs/
  CLAUDE.md  README.md
```

Personal data lives in a second, private repo, cloned to `~/.config/dotfiles/private/` on personal machines only. See Private layer.

Files in the repo drop their leading dot (`vim/vimrc`, not `.vimrc`), so they are visible in the repo and cannot be confused with the live file. `worksetup.sh` and the root `.vimrc`, `.tmux.conf` and `.bash_aliases` are removed only after the new layout has been verified on at least one machine.

## How files reach $HOME

Files only I edit are symlinked into the repo. Files that installers also edit stay as real local files that load the repo version. That keeps tool edits and machine-specific settings out of the repo.

**Why not symlink everything:** `conda init`, rustup, nvm, sdkman and similar tools append to `~/.zshrc`, `~/.bashrc` or `~/.zprofile`. Through a symlink, their edits would either land in the public repo or replace the link with a regular file, so the machine silently stops following the repo.

**Mechanism A: symlink.** `~/.vimrc` points to `<repo>/vim/vimrc`. Editing either one edits the repo.

**Mechanism B: local stub plus include.** `~/.zshrc` stays a real file owned by the machine. The installer adds one marked block at the top, with the repo's actual location written in, relative to `$HOME`:

```sh
# >>> dotfiles >>>
[ -f "$HOME/dotFiles/shell/zshrc" ] && source "$HOME/dotFiles/shell/zshrc"
# <<< dotfiles <<<
```

Everything below the block is local: the conda block, machine-only settings, one-off experiments. Local lines come after the shared ones, so they can override them. The `[ -f … ]` guard means a missing or moved repo never breaks the shell. The block is added once, is found again by its markers, and existing content is never removed.

| Live file | Mechanism | Repo file | What stays local |
| --- | --- | --- | --- |
| `~/.vimrc` | A: symlink | `vim/vimrc` | nothing |
| `~/.tmux.conf` | A: symlink | `tmux/tmux.conf` | nothing |
| `~/.tmux/plugins/tmux/scripts/task_timew.sh` | A: symlink, after plugins | `tmux/task_timew.sh` | nothing |
| `~/.zshrc` (macOS) | B: `source` | `shell/zshrc` | conda, machine-only settings |
| `~/.zprofile` (macOS) | B: `source` | `shell/zprofile` | rbenv, other tool inits |
| `~/.zshenv` (macOS) | B: `source` | `shell/zshenv` | cargo env |
| `~/.bashrc` (Linux) | B: `source` | `shell/bashrc` | distro defaults already in the file |
| `~/.gitconfig` | B: `[include] path =` | `git/gitconfig` | default identity, and the generated `includeIf` block (see Git identities) |
| `~/.taskrc` | B: `include` | `task/taskrc` | `data.location` and the task data itself (not synced), contexts, private projects. The shared `task/taskrc` uses only settings valid in both 2.6 and 3.x |

This table is not hard-coded in the installer. It is the content of `links.txt` (see Declared lists and --adopt). The zsh files are managed on macOS only, so bash-only servers do not get empty `~/.zshrc` files.

`shell/zshrc` and `shell/bashrc` both source `shell/load.sh`, which runs the shell load order described under Private layer. `shell/zprofile` sets up Homebrew for the right architecture (`/opt/homebrew` or `/usr/local`) and runs tool inits such as rbenv only when the tool exists (`command -v rbenv && eval …`).

**bash on Linux.** `shell/bashrc` starts with `[[ $- == *i* ]] || return`. The stub sits at the top of `~/.bashrc`, before Ubuntu's own interactive check, so without this guard the shared config would also run for `scp` and `ssh host command`, where any output breaks the transfer. `~/.bash_aliases` stays a local file, because Ubuntu's default `~/.bashrc` already sources it. It becomes the bash equivalent of the local part of `~/.zshrc`.

**Shell-aware edit aliases** in `shell/aliases.sh`, so the same names work everywhere:

| Alias | zsh (macOS) | bash (Linux) |
| --- | --- | --- |
| `vbrc` | `vim ~/.zshrc` | `vim ~/.bash_aliases` |
| `sbrc` | `source ~/.zshrc` | `source ~/.bashrc` |
| `vtrc` | `vim ~/.taskrc` | `vim ~/.taskrc` |

These edit the **local** files. Shared aliases are edited in the public repo, and personal ones in the private layer.

## Declared lists and --adopt

What the installer manages is data, not code. Managed files are listed in `links.txt` and git-cloned add-ons in `addons.txt`. Adding a file or an add-on means adding one line, not changing `install.sh`. `--adopt` brings a live file under management and writes its `links.txt` line for me.

**`links.txt`: managed files**

```
# repo path            live path                                      mechanism
vim/vimrc              ~/.vimrc                                       link
tmux/tmux.conf         ~/.tmux.conf                                   link
tmux/task_timew.sh     ~/.tmux/plugins/tmux/scripts/task_timew.sh     link:late
shell/zshrc            ~/.zshrc                                       stub:sh      macos
shell/zprofile         ~/.zprofile                                    stub:sh      macos
shell/zshenv           ~/.zshenv                                      stub:sh      macos
shell/bashrc           ~/.bashrc                                      stub:sh      linux
git/gitconfig          ~/.gitconfig                                   stub:gitconfig
task/taskrc            ~/.taskrc                                      stub:taskrc
```

- **Component** is the first folder of the repo path (`vim`, `tmux`, `shell`, `git`, `task`). `--only <component>` uses it to select lines.
- **Mechanism** is `link` (A), `link:late` or `stub:<kind>` (B). `link:late` is a symlink made after plugin installs, for files that live inside a plugin's folder. The stub kind picks the include line: `sh` writes the guarded `source` block, `gitconfig` writes `[include] path = …`, and `taskrc` writes `include …`. Each is wrapped in the same `>>> dotfiles >>>` markers, using the file's own comment character.
- **An optional fifth column** limits a line to `macos` or `linux`. Lines without it apply everywhere.
- **Paths:** only a leading `~/` is expanded, to `$HOME/`. Lines are never passed to `eval`, so a stray `$(…)` in the file cannot run.
- **Order matters:** lines run top to bottom, in two passes (see Run order). `link` and `stub` lines run before plugin installs, because Vundle and TPM read `~/.vimrc` and `~/.tmux.conf` to know what to install. `link:late` lines run after, so `task_timew.sh` links into the Dracula folder TPM has just created. Creating that folder earlier would make TPM think Dracula is already installed.
- **Parsing** is a plain `while read -r repo live mech os` loop, which works in bash 3.2.

**`addons.txt`: git-cloned add-ons**

```
# component  repo URL                                        destination
vim          https://github.com/VundleVim/Vundle.vim.git     ~/.vim/bundle/Vundle.vim
tmux         https://github.com/tmux-plugins/tpm             ~/.tmux/plugins/tpm
```

The component ties each add-on to `--only`, the same way as in `links.txt`.

| Destination state | Normal run | `--check` |
| --- | --- | --- |
| Missing | `git clone --depth 1` | reports "missing" |
| Git repo with the same remote URL | skip; with `--update-addons`, `git pull --ff-only` | "ok" |
| Git repo with a different remote, or not a git repo | leave it alone, report it | reports "conflict" |

After add-ons and the first linking pass, the installer runs the plugin steps that belong to them: `vim +PluginInstall +qall` for Vundle (which also installs atom-dark) and TPM's `bin/install_plugins`. These stay in code because each tool triggers its install differently.

**`--adopt <live path>`: bring a live file under management**

```
./install.sh --adopt ~/.config/htop/htoprc [--as htop/htoprc]
```

1. **Refuse** if the path is not under `$HOME`, is not a regular file (directories are out of scope for now), is already in `links.txt`, or is a stub-managed file such as `~/.zshrc`. For stub files, shared lines are moved into the repo file by hand, and the local rest stays where it is.
2. **Scan for PII** with the same patterns as the pre-commit hook. On a hit, stop and show the lines. The file is not adopted until it is clean, or the private lines have moved to the private layer or a local file.
3. **Choose the repo path:** `--as` if given. Otherwise the path relative to `$HOME` with its leading dot dropped, so `~/.config/htop/htoprc` becomes `config/htop/htoprc`. Use `--as` to follow the by-tool layout (`htop/htoprc`).
4. **If the repo path is new:** back up the live file, copy it into the repo, check that the two are identical (`cmp`), replace the live file with a symlink, and append a `link` line to `links.txt`.
5. **If the repo path already exists** (the same file adopted on another machine): show the diff and ask. The choices are: *keep repo* (live file backed up, then linked), *take live* (repo file overwritten with the live one, then linked), *merge by hand* (opens `vimdiff`, then asks again), or *skip*. *Take live* is refused while the repo file has uncommitted changes, because git could not bring those back.
6. **Record** the action as `adopted` in the backup manifest, so `--restore` removes the link and puts the original file back. The repo file stays: whether to keep it is a `git` decision.
7. **Never commit.** The run ends by printing the files to review and `git add`.

`--adopt` supports `--dry-run`. The same *keep repo / take live / merge / skip* prompt is used by a normal run when a linked file differs from the repo. That makes consolidating a drifted Linux machine one command per file.

## Profiles

A profile is a small overlay on the shared base: extra packages plus extra shell config. There are two to start with, `personal` and `office`, and `base` means no overlay.

| Profile controls | Base (every machine) | Profile overlay |
| --- | --- | --- |
| Packages | `packages/common.txt` | `packages/<profile>.txt` |
| Shell config | `shell/aliases.sh` | `shell/profiles/<profile>.sh` |
| Mac apps (casks) | `cask:` entries in `common.txt` (iTerm2) | `cask:` entries in `packages/<profile>.txt` |
| Private settings | never in the public repo | private layer (personal), or `office.local.sh` on the office machine |

**Choosing and remembering the profile**

- First run: `./install.sh --profile personal`. With no flag on a first run, the installer asks.
- The choice is saved in `~/.config/dotfiles/profile`, a local file. Re-runs and `shell/load.sh` read it from there.
- To switch profiles, run `--profile office` again. That adds the new packages and swaps which profile file the shell loads, but does not uninstall the old profile's packages.

**The office profile and the public repo.** Employer names, internal hostnames, VPN aliases and work email cannot go into the repo. `shell/profiles/office.sh` therefore holds only generic work tools. Anything specific goes in `~/.config/dotfiles/office.local.sh`, which the shell load order picks up. That file stays on the office machine only. Work content never goes into either of my GitHub repos.

**The personal profile** holds non-identifying things only, such as packages and generic aliases. Project-specific aliases, cloud-drive paths, LAN hosts and VPN aliases go to the private layer (`private/shell/personal.sh`), which the shell load order picks up when it exists.

## Private layer

Two repos with different audiences. `dotFiles` is public and holds everything any machine needs. `dotFiles-private` is a small private repo that holds everything about me. The private repo is cloned only on personal machines, into `~/.config/dotfiles/private/`. Office machines never clone it, so they need no GitHub login and carry no personal data.

**Where each kind of file lives**

| Location | Synced? | On which machines | Holds |
| --- | --- | --- | --- |
| `dotFiles` (public repo) | `git pull` | all | tools, shared config, installer, profiles without personal content |
| `~/.config/dotfiles/private/` = `dotFiles-private` | `git pull` | personal laptops and servers | personal aliases, git identities list, hostnames, PII patterns, unscrubbed notes |
| `~/.config/dotfiles/` (other files) | never | this machine only | chosen profile, `office.local.sh` on office machines |
| local `~/.zshrc`, `~/.bashrc` below the stub | never | this machine only | conda and other tool-written blocks, one-off experiments |

**Private repo layout**

```
dotFiles-private/                # cloned to ~/.config/dotfiles/private/
  git-identities                 # account, folder, ssh key (see Git identities)
  shell/personal.sh              # personal aliases and paths
  shell/hosts/<short-hostname>.sh  # optional: extras for one machine
  pii-patterns                   # words the public repo's hook must block
  notes/                         # unscrubbed audits and design notes
```

It holds no scripts. The public installer reads it. SSH keys and tokens do not go here either: a private repo still leaks through a lost laptop or a future visibility change.

**Shell load order** (later overrides earlier), implemented once in `shell/load.sh` for both zsh and bash

1. `shell/aliases.sh`, shared.
2. `shell/profiles/<profile>.sh`, from the public repo.
3. `private/shell/<profile>.sh`, if it exists.
4. `private/shell/hosts/<short-hostname>.sh`, if it exists.
5. `~/.config/dotfiles/<profile>.local.sh`, if it exists: this machine only.
6. The rest of the local `~/.zshrc` or `~/.bashrc`, below the stub.

Every step is guarded with `[ -f … ]`, so a machine without the private layer still gets a working shell.

**How the installer handles it**

- **Personal profile, private layer missing:** it offers to clone `git@github.com:rmadhira/dotFiles-private.git` over SSH. The identities list is inside that repo, so it cannot say which key to use. The installer therefore uses the naming convention: `~/.ssh/<owner>_key` if it exists, where the owner is taken from the public repo's URL (`rmadhira`), and otherwise ssh's defaults. With no working key, it prints the `ssh-keygen` command and how to add the key to GitHub, skips this step, and finishes the basic setup. Re-running later picks it up.
- **Office and base profiles:** the private layer is never cloned or offered.
- **`--check`** reports the private layer as missing, clean, behind its remote, or with uncommitted changes.
- **The installer never commits or pushes** in either repo.

**Setting up each kind of machine**

| Machine | Steps |
| --- | --- |
| Office laptop | `git clone https://github.com/rmadhira/dotFiles.git ~/dotFiles`, then `./install.sh --profile office`. No login needed. |
| New personal laptop | Same clone, then `./install.sh --profile personal`. Create the SSH key with the printed command and add it to GitHub, then re-run to pull in the private layer and identities. |
| Personal server | Same as a personal laptop. SSH keys are usually already there. |

## Git identities

On personal machines, the git identity follows the folder. Each GitHub account gets its own folder under `~/projects/`, and repos inside it commit with that account's name, email and SSH key. Office machines do not get personal identities. The public repo holds only the mechanism. The list of identities and the emails live in the private layer, and the keys stay on each machine.

**How it works today on the Mac (keep it).** `~/.gitconfig` has one `includeIf "gitdir:~/projects/<account>/"` per account, pointing to `~/.gitconfig.<account>`. Each of those sets `user.name`, `user.email`, `github.user` and `core.sshCommand = "ssh -i ~/.ssh/<account>_key"`.

**What the installer adds**

- **A list of identities** in the private layer, `private/git-identities`, never in the public repo:
  ```
  # account      folder                   ssh key                  name           email
  <account-a>    ~/projects/<account-a>/  ~/.ssh/<account-a>_key   <account-a>    <id>+<account-a>@users.noreply.github.com
  <account-b>    ~/projects/<account-b>/  ~/.ssh/<account-b>_key   <account-b>    <id>+<account-b>@users.noreply.github.com
  ```
- **From that list,** the installer writes the `includeIf "gitdir/i:…"` lines inside a marked block in the local `~/.gitconfig`, using the same markers as stubs. It also creates each folder if it is missing.
- **The dotfiles repos themselves are covered too.** They usually sit outside `~/projects/<account>/`: the public repo at `~/dotFiles` on new machines, and the private layer at `~/.config/dotfiles/private/`. The block also maps both locations to the repos' owner account. Otherwise `user.useConfigOnly` (below) would block commits in them, and pushes would use the wrong key.
- **It creates `~/.gitconfig.<account>` only if the file is missing,** filled from the list's name, email and key. Existing identity files are never rewritten; `--check` reports how they differ from the list instead.
- **SSH keys are never created, copied or moved** (a non-goal). When a key is missing, `--check` reports it and prints the exact command to create one, for example `ssh-keygen -t ed25519 -f ~/.ssh/<account>_key -C "<account>@<machine>"`, plus a reminder to add the public key to GitHub with a title naming the machine.
- **It runs for the `personal` profile only.** On a new personal laptop, the list arrives with the private layer, so nothing is copied by hand.

**Two fixes to the current setup**

1. **Add `-o IdentitiesOnly=yes`:** `core.sshCommand = "ssh -i ~/.ssh/<account>_key -o IdentitiesOnly=yes"`. Without it, ssh first offers every key loaded in `ssh-agent`. GitHub picks the account from the first key it accepts, so a push can authenticate as the wrong account. Identity files the installer creates include this, and `--check` warns when an existing one lacks it.
2. **Set `user.useConfigOnly = true` in the shared `git/gitconfig`.** Outside the identity folders, git then refuses to commit rather than guessing an identity from the hostname. On office machines, the local `~/.gitconfig` sets the work identity as the default, so nothing changes there. Before this is linked on a machine, `--check` lists any repos outside the identity folders, since commits in them will start failing.

Also use `gitdir/i:` instead of `gitdir:`. The match then ignores letter case, which suits macOS's case-insensitive disk and is harmless on Linux.

**HTTPS remotes bypass all of this.** `core.sshCommand` only applies to SSH remotes. With an HTTPS remote, as this repo has today, the account comes from whatever login the credential helper has stored. `--check` lists repos inside identity folders that use HTTPS remotes. A fresh machine still clones this repo over HTTPS, since it is public and no key exists yet. On personal machines, `--check` then prints the command to switch the remote to SSH once the key is in place. Office machines keep HTTPS and never push.

**Commit email: GitHub noreply, not my real address.** Every commit records an author email, and in a public repo anyone can read it (`git log`, or `.patch` on a commit URL). All existing commits in this repo carry my real address. From now on, identities for accounts with public repos use GitHub's noreply address, `<id>+<login>@users.noreply.github.com`. Look it up with `gh api user --jq '"\(.id)+\(.login)@users.noreply.github.com"'`.

- **Scope is the folder, not the visibility.** The change applies to every repo under that account's `~/projects/<account>/` folder, private ones included. That is harmless: noreply commits still link to my account and count on my contribution graph. A single repo that needs the real address overrides it with `git -C <repo> config user.email …`.
- **Past commits stay as they are.** Rewriting history would need a force-push, and existing clones keep the old commits anyway.
- **Two-step rollout:**
    1. Switch `user.email` in the identity file on each machine as it is set up. The value comes from the email column of `private/git-identities`. Existing identity files are edited by hand, because the installer never rewrites them; `--check` shows the difference.
    2. Only after every machine I commit from has switched, turn on GitHub's "Keep my email addresses private" and "Block command line pushes that expose my email". The block is account-wide: it would reject pushes, to public and private repos alike, from any machine still using the real address.
- **`--check`** warns when an identity for an account with public repos uses an email that is not a noreply address.
- **Reversible:** both the local setting and the GitHub options can be switched back at any time.
- **Per account:** `<account-b>` has its own identity file and GitHub settings, and is decided separately.

The pre-commit hook covers file contents, but it cannot see commit metadata. The GitHub push block covers that gap.

**Servers: full identities, one key per server.** I develop and deploy on both servers, pushing as well as pulling, so they are set up like personal laptops, with one difference: keys.

- **Identity config** (folders, names, noreply emails) comes from `private/git-identities`, the same as on laptops.
- **Each server gets its own key for each account**, generated on that server. The file name is the same everywhere (`~/.ssh/<account>_key`), so the identities list works unchanged, but the key inside differs per machine.
- **Never copy a key between machines.** A key per machine can be revoked alone if that machine is lost or compromised. A shared key would force a rotation everywhere.
- **Existing keys are renamed by hand to the convention.** Server A's keys use other file names. In phase 6, `--check` reports the mismatch and prints the `mv` commands, plus the edit needed in each identity file. The installer never moves keys itself. The same step compares key fingerprints (`ssh-keygen -lf`) with the other machines, to find any key that was copied rather than generated there.
- **GitHub key titles name the machine and account,** for example `server-a / <account-b>`, so the list under Settings → SSH keys shows exactly what to revoke. Review that list when a machine is retired.
- **Always with `IdentitiesOnly=yes`** (see above). On a server that uses both accounts, this is what keeps pushes on the right account.
- **Optional hardening:** a passphrase on the key, unlocked once per login through `ssh-agent`. A cron job that only pulls one repo can use a separate read-only deploy key without a passphrase, so the main key never has to be unlocked unattended.

These keys give full access to everything that account can reach. Keeping the servers updated and SSH access locked down matters as much as the keys themselves. That is outside this design.

**Office machines: no personal identities.** Personal SSH keys on employer hardware are a risk if the device is monitored, audited or wiped, and are often against policy. Keeping them off also rules out committing work code under a personal account, or the reverse. The office profile skips identity setup. The work identity is the plain default in the local `~/.gitconfig`, often managed by the employer. This repo can still be cloned over HTTPS on an office laptop for the shared config.

## Package management

Homebrew on macOS and apt on Ubuntu/Debian, driven by plain-text package lists that both platforms share. Tools that are not packages, Vundle and TPM, are installed by git clone. vim plugins, including the atom-dark colour scheme, come through Vundle.

**Before the installer: getting git on a fresh Mac.** `xcode-select --install` (the Command Line Tools) provides git, which is needed to clone the repo. Ubuntu ships git. This is the only manual step before `./install.sh`.

**Run order.** A full run has nine numbered steps, the numbers the output shows (`[3/9]`). `--only` and `--link-only` run the relevant subset in the same order.

1. **Preflight:** detect the platform, read the profile, check the repo. Nothing is changed.
2. **Package manager:** `pkg_bootstrap`. On macOS: Homebrew through its official installer if missing, then its `shellenv` is loaded for the rest of the run. On Linux: `sudo -v` first, so the password is asked once, up front, with a line saying why. Then `sudo apt update`, and the charm.sh repo only if glow is missing **and** apt has no glow package (26.04 has one; 22.04 probably does not).
3. **Packages:** `common.txt`, then the profile's list.
4. **Add-ons:** git clones from `addons.txt` (Vundle, TPM).
5. **Links and stubs:** `link` and `stub` lines from `links.txt`.
6. **Plugins:** `vim +PluginInstall +qall` and TPM's `bin/install_plugins`, so no manual `prefix + I` is needed. This needs step 5, because both tools read their config file to know what to install.
7. **Late links:** `link:late` lines, which point into folders the plugins just created.
8. **Private layer and git identities** (personal profile only): clone or check the private layer, then write the identity block from its list.
9. **Finish:** turn on the repo's pre-commit hook, then print the summary.

**Base tool set (`common.txt`)**

| Tool | brew | apt | Notes |
| --- | --- | --- | --- |
| git | git | git | |
| vim | vim | vim | Homebrew vim replaces the older macOS vim |
| tmux | tmux | tmux | |
| curl | (system) | curl | macOS ships curl |
| wget | wget | wget | missing on this Mac today |
| glow | glow | glow | in Ubuntu's apt from 26.04; older releases need the charm.sh repo |
| taskwarrior | task | taskwarrior | versions may differ (Ubuntu 22.04 and 26.04: 2.6, Homebrew: 3.x); fine, because task data is not synced |
| timewarrior | timewarrior | timewarrior | |
| fzf | fzf | fzf | fuzzy file and history search |
| ripgrep | ripgrep | ripgrep | command is `rg` |
| jq | jq | jq | |
| tree | tree | tree | |
| gh | gh | skipped | macOS only for now (apt `-` in `map.txt`) |
| htop | htop | htop | |
| bat | bat | bat | apt installs the command as `batcat`; `aliases.sh` adds `bat` → `batcat` on Linux |
| taskwarrior-tui | taskwarrior-tui | skipped | macOS only for now; not in Ubuntu apt |
| taskopen | taskopen | skipped | macOS only; not in apt on 22.04 or 26.04 (an existing manual install is left alone) |
| mosh | mosh | mosh | |
| iTerm2 | `cask:iterm2 iTerm.app` | skipped | macOS app only; a copy installed by hand counts as installed |
| Vundle, TPM | git clone | git clone | not packages |
| vim-atom-dark | Vundle plugin | Vundle plugin | installed by `:PluginInstall`, no separate clone or copy |

Every tool in this table is in the base list, so the `personal` and `office` package lists start empty. Installed tools are skipped, so a longer list costs nothing on machines that already have them. On this Mac, git, vim, tmux, glow, task, timew, tree, gh, taskwarrior-tui, taskopen, mosh and iTerm2 are already installed. wget, fzf, ripgrep, jq, htop and bat are missing.

The list format is one package per line, `#` for comments, and `cask:` for Mac-only apps, which are skipped on Linux. A cask line also names its app bundle (`cask:iterm2 iTerm.app`). Without it, a Mac where the app was installed by hand makes `brew install --cask` fail with "It seems there is already an App at …", and the run stops. By default the list name is used for both brew and apt. `map.txt` covers the exceptions with three columns, list name, brew name and apt name, where `-` skips that platform:

```
# list name        brew             apt
taskwarrior        task             taskwarrior
curl               -                curl            # macOS ships curl
gh                 gh               -               # macOS only for now
taskwarrior-tui    taskwarrior-tui  -               # not in Ubuntu apt
taskopen           taskopen         -               # not in Ubuntu apt (22.04, 26.04)
```

Every list is parsed with plain `while read` loops, without associative arrays, so it works in bash 3.2.

## Platform layer

`install.sh` is a thin wrapper: it detects the platform, sources exactly one platform file, then runs the shared steps in `lib/common.sh`. Only what really differs between operating systems lives in the platform files. Everything else is written once, so a fix cannot land on one OS and miss another.

**Why not one complete script per OS.** A per-OS script still has to run on bash 3.2 on a fresh Mac, so the split does not remove that constraint. Checking, backups, linking, stubs, profiles and restore are the same everywhere. Copying them into each OS script would create the same drift this redesign removes.

**Detection**

1. `uname -s` = `Darwin` means `macos`.
2. `uname -s` = `Linux` means reading `/etc/os-release`: `ID` or `ID_LIKE` containing `debian` or `ubuntu` means `debian`; `fedora` or `rhel` means `fedora` once that file exists.
3. Anything else stops with the detected values and a clear message, before any change is made.
4. `--platform <name>` overrides detection, for testing and for unusual distros.

**The platform functions.** Every platform file defines exactly these functions and nothing else. `common.sh` calls them and never calls `brew`, `apt`, `sed -i`, `stat` or `readlink` directly.

| Function | What it does | macOS | Debian/Ubuntu |
| --- | --- | --- | --- |
| `pkg_bootstrap` | Gets the package manager ready | Xcode CLT check; install Homebrew if missing; load `shellenv` | `sudo -v` (one password prompt, up front); `sudo apt update`; add the charm.sh repo only if apt has no glow |
| `pkg_installed <name>` | Is this package already installed? | `brew list --formula`; for casks, `brew list --cask` **or** the app bundle already in `/Applications` or `~/Applications` (reported as "ok, installed outside Homebrew" and never reinstalled) | `dpkg -s` |
| `pkg_install <name>…` | Installs packages; `cask:` entries only on macOS | `brew install`, `brew install --cask` | `sudo apt install -y`; skips `cask:` entries |
| `sed_inplace <expr> <file>` | Edits a file in place | `sed -i ''` | `sed -i` |
| `file_mtime <file>` | Modification time, for backups and logs | `stat -f %m` | `stat -c %Y` |
| `resolve_path <path>` | Absolute path with symlinks followed | `cd` + `pwd -P` loop (no `readlink -f` on older macOS) | `readlink -f` |

Adding a distro means adding one file under `lib/platform/` that defines these six functions, plus one detection rule. `common.sh` does not change.

## install.sh interface

One script with a mode for each job. The two read-only modes are the default way to start on any machine.

```
./install.sh [mode] [--profile base|personal|office] [--only packages|vim|tmux|shell|git|task|private] [--platform macos|debian] [--yes] [--verbose]
```

| Mode | Changes anything? | What it does |
| --- | --- | --- |
| `--check` | No | Per managed file: missing, identical, differs (with `diff`), already linked, link broken, or link replaced by a regular file. Also lists missing packages and uncommitted changes in the repo. |
| `--dry-run` | No | Prints every action a real run would take, in order. |
| `--report` | No | Prints one redacted, pasteable block: platform, versions, `--check` results and the latest failure. See Verbose output and error reports. |
| (none) | Yes | Full install, following the Run order. Asks before each file that differs, unless `--yes` is given. |
| `--link-only` | Yes | Links and stubs only, no packages. For machines where I cannot install software. |
| `--adopt <path> [--as <repo path>]` | Yes | Moves a live file into the repo, links it and adds it to `links.txt`. See Declared lists and --adopt. |
| `--update-addons` | Yes | `git pull --ff-only` on every add-on in `addons.txt` whose remote matches. |
| `--restore [timestamp]` | Yes | Puts back files from a backup (the latest by default) and removes the links and stub blocks. |
| `--uninstall-hooks` | Yes | Removes the repo's pre-commit hook. |

`--only` limits a run to one component, which is how the execution phases below roll things out one at a time. A component covers its `links.txt` lines, its add-ons and its plugin step: `vim` means the vimrc link, Vundle and `:PluginInstall`. `git` includes the identity block, and `private` is the private layer clone. Every real run writes a markdown log to `~/.local/state/dotfiles/install-<timestamp>.md`, not the current directory.

The run ends with a summary: what was installed, linked, stubbed, skipped and backed up, plus the manual steps left over.

## Verbose output and error reports

The Linux servers have no Claude access, so the installer must explain itself well enough that a pasted error report is all it takes to fix it. The loop is: run on the server, paste the failure report here, fix in the repo on the Mac, push, then `git pull` and re-run on the server. Re-running is safe because every step is idempotent.

**Normal output**

- Numbered step headers: `[4/9] Installing add-ons`.
- One line per action with a fixed result word: `ok` (already right), `done` (changed), `skip` (not for this platform or profile), `FAIL`.
- Every external command is printed before it runs, prefixed with `+` (`+ sudo apt install -y fzf`), and its output is shown and logged.
- The first lines show what the run detected: platform, OS release, architecture, bash version, profile, repo commit, and whether the repo has uncommitted changes.

**On failure**

The installer stops at the first failure. Nothing later runs on top of a broken step. It prints one block, designed to be copied whole:

```
==================== dotfiles: FAILED ====================
step      : [3/9] Installing packages
action    : pkg_install fzf
command   : sudo apt install -y fzf
exit code : 100
location  : lib/platform/debian.sh:42 (pkg_install)
platform  : debian | Ubuntu 22.04.5 LTS | x86_64 | bash 5.1.16
repo      : a1b2c3d (clean) | profile: personal
last output:
  E: Unable to locate package fzf
log       : ~/.local/state/dotfiles/install-20260925-120000.md
next      : paste this block, or run ./install.sh --report
===========================================================
```

This uses bash's `ERR` trap with `set -eE`, `$BASH_COMMAND`, `BASH_SOURCE` and `BASH_LINENO`, all of which work in bash 3.2. Output from each external command is also captured to a temporary file so its last 20 lines can be shown.

**`--verbose`** adds a line-by-line trace (`set -x`, with `PS4` showing file and line) to the log file only, so the terminal stays readable.

**`--report`** is read-only. It prints one pasteable block: the detection lines above, `--check` results, versions of every managed tool, the add-on states, and the failure block from the latest log, if there is one.

**Redaction.** The failure block, `--report` and the log replace `$HOME` with `~`, the username with `<user>`, and the hostname with `<host>`. Reports can be pasted anywhere without editing, and nothing personal can end up in a fix by copy and paste. SSH key file names can contain personal words (the phase 0 survey showed one that does), so `--report` shows only whether each key from the identities list exists, never a raw listing of `~/.ssh`.

**Exit codes:** 0 success, 1 a step failed, 2 wrong usage, 3 unsupported platform. Logs are kept, and the last 20 remain in `~/.local/state/dotfiles/`.

## Safety: backups, restore and drift

Every file the installer touches is backed up first, and one command undoes a run. Drift is caught by `--check`, not discovered when something breaks.

**Backups**

- Location: `~/.local/state/dotfiles/backup/<YYYYmmdd-HHMMSS>/`, with the home-relative path kept (`.../backup/20260925-120000/.vimrc`).
- A manifest (`manifest.txt`) in each backup records every action: `linked`, `stubbed` (including the git identity block), `cloned`, `created` (a new identity file), `adopted`. `--restore` replays it in reverse.
- Before a symlink: the existing file is **moved** (`mv`, never `rm`) into the backup.
- Before adding a stub block: the file is **copied** into the backup, then edited in place, so its inode and permissions stay the same.
- Backups are never deleted automatically.

**Decisions for each file during a real run**

| Live state | Action |
| --- | --- |
| Missing | Link or create the stub; nothing to back up |
| Already the right symlink, or stub block present | Skip |
| Identical to the repo file (symlink targets only) | Back up, then link, without asking |
| Differs from the repo file | Show the diff, ask: keep repo (live copy to backup, then link) / take live (into the repo, then link) / merge by hand / skip. `--yes` means keep repo. |
| Symlink to somewhere else | Ask; never followed or overwritten silently |

**Drift after setup.** `--check` catches the three ways a machine can fall out of step with the repo:

- Someone edited a symlinked file. This shows up as uncommitted changes in the repo, so `git status` catches it too.
- A tool replaced a symlink with a regular file. Reported as "link replaced", with a diff against the repo version.
- A stub block was removed from `~/.zshrc`. Reported as "stub missing".

**Rollback levels**

1. A single file: copy it back from the latest backup folder by hand.
2. The whole run: `./install.sh --restore`.
3. The repo itself: every phase is a separate commit or branch, so `git revert` undoes it.
4. Last resort: comment out the stub line in `~/.zshrc`. The shell then runs only its local content, exactly as before the dotfiles existed.

## Keeping PII out of the public repo

The repo is public, so PII is kept out in three layers: where content lives, a pre-commit hook, and a review step before each push.

**Layer 1: where content lives.** Private content has a home outside the repo, so there is no reason to commit it.

| Kind of content | Where it goes |
| --- | --- |
| Names and emails of my git identities | private layer `git-identities`, written into local `~/.gitconfig.<account>` files |
| Personal aliases, paths (cloud drives, project folders), hostnames, private IPs, mosh targets | private layer: `private/shell/personal.sh`, `private/shell/hosts/` |
| SSH host definitions, keys | local `~/.ssh/`, never in either repo |
| Anything work-related | `~/.config/dotfiles/office.local.sh`, on the office machine only; never in either repo |
| Tool-generated blocks (conda, nvm, rustup) | local `~/.zshrc` / `~/.bashrc` |

Repo files refer to home as `$HOME` or `~`, never `/Users/<name>` or `/home/<name>`.

**Layer 2: pre-commit hook** (`hooks/pre-commit`, turned on by `install.sh` through `git config core.hooksPath hooks`). It checks the staged lines and blocks the commit on:

- `/Users/<anything>` or `/home/<anything>` literal paths
- email addresses (except `noreply` addresses)
- private IPv4 ranges: `10.`, `172.16–31.`, `192.168.`
- markers of tool-generated blocks: `conda initialize`, `NVM_DIR`, `.cargo/env` with a literal path
- likely secrets: `token`, `secret`, `password`, `api_key` followed by `=`
- my own words from `private/pii-patterns` (hostnames, account names), if the private layer is present

A deliberate false positive can be committed with `git commit --no-verify`.

**Layer 3: review before push.** Each phase ends with reading the diff against the remote branch (`git diff origin/<branch>`) before `git push`.

**Content already public.** Git history has an old home-directory path in `.bash_aliases` that shows a username and a project name. Plan: leave the history alone and stop repeating it. Rewriting history would need a force-push. Separately, my real email is public in the metadata of every existing commit. New commits use the GitHub noreply address (see Git identities).

## Execution phases

Eight phases, ordered by risk. The public part is built first and proven on the two **fresh** machines, where there is nothing to break. The two machines **in use** stay read-only (`--check`, `--dry-run`, `--report`) until the installer has made a complete real run on both macOS and Linux. Server A goes last: it is the oldest machine, runs conda and a cron job, and has no Claude access.

Work happens on a branch, `redesign`, which is pushed but only merged into `master` in phase 7. Until then, every machine clones it with `git clone -b redesign`. It is public, so no login is needed.

| # | Phase | Machines | Changes a machine? | Done when | Rollback |
| --- | --- | --- | --- | --- | --- |
| 0 | Branch; commit this design, `CLAUDE.md` and `tools/survey.sh`. Then run the survey on every machine (server B first, then the office Mac, server A, the personal Mac) and add the findings to Current state | all four (read-only) | No: only the repo is cloned | Branch pushed; a survey from each machine is reviewed here | Delete branch |
| 1 | Public repo content: new layout, merge in the live `.tmux.conf`, write `shell/*` (including `load.sh`) from the shared part of `.zshrc`, `silent! colorscheme` in `vim/vimrc`, package lists, `links.txt`, `addons.txt`, pre-commit hook | none | No | `bash -n` passes on all scripts; hook blocks a planted test path; old root files still present | `git revert` |
| 2 | Installer, read-only: wrapper, platform detection, both platform files, list parsing, preflight, `--check`, `--dry-run`, `--report`, output format, failure block, redaction. Then run the read-only modes everywhere | all four | No: only the repo is cloned | `shellcheck` clean; Macs run it with `/bin/bash`. Personal Mac: `--check` matches Current state. Server A: `--report` pasted here and reviewed. Fresh machines: `--check` shows everything missing, and `--dry-run` lists a complete install | `git revert` |
| 3 | Installer, write path: packages, add-ons, links, stubs, plugins, late links, backups, `--restore`, `--adopt`, keep-repo/take-live prompt. Real runs on the fresh machines only: office Mac `--profile office`, server B `--profile base`. Existing machines: `--dry-run` again with the finished code | office Mac, server B (real); personal Mac, server A (dry run) | fresh machines only | Both full runs succeed; an immediate re-run reports only `ok`; `--restore` then a re-run gives the same result; an `--adopt` + `--restore` round-trip leaves a test file byte-identical; a deliberately broken package name produces a usable failure block | `--restore`; worst case, reinstall a fresh machine |
| 4 | Link the personal Mac, one `--only` at a time: packages, vim, tmux, git, task, then shell | personal Mac | Yes | Only the missing packages are installed (wget, fzf, ripgrep, jq, htop, bat); vim, tmux and a new terminal work after each step; after the git step, a test commit in each identity folder shows the right author | `--restore`, rollback levels, `brew uninstall` the new packages |
| 5 | Private layer and identities: create `dotFiles-private` (private) and fill it from the personal Mac; add the private-layer clone and identity block to the installer; switch the personal Mac to the noreply email. Then move server B to `--profile personal`, with its own keys | personal Mac, server B | Yes | A new shell loads the private aliases on both; commits in both dotfiles repos and each identity folder show the right noreply author; the office Mac's `--dry-run` shows no private-layer steps | Delete the private repo and `--restore`; the public setup still works without it |
| 6 | Server A: `--check`, bring drift worth keeping into the repo (take-live prompt or `--adopt`), then link one `--only` at a time, shell last. First, a full install in an `ubuntu:22.04` container on server B, which has Docker, as a rehearsal | server A | Yes | `--check` clean; a new login shell works; the next scheduled run of each of its four cron jobs succeeds (the shared `bashrc` exits early for non-interactive shells, so cron behaviour should not change) | `--restore` on server A |
| 7 | Clean up: remove `worksetup.sh` and the old root dotfiles, write `README.md`, merge to `master`. Then turn on GitHub email privacy and the push block, once every personal machine uses the noreply email | none | No | README steps work as written | `git revert` |

**Rules during execution**

- One phase per session. Each ends with `--check`, a review of `git diff`, and a commit.
- For every shell step on a machine in use (phases 4 and 6), keep a second terminal or SSH session open that was started **before** the change. If the new shell breaks, fix it from there.
- A phase that fails stops the plan. Roll back, update this doc, then retry.
- **Office Mac:** check the employer's policy before phase 3. Homebrew needs admin rights to create `/opt/homebrew`, and device management may block it or require approval. If Homebrew is not allowed, the office Mac uses `--link-only`, and the fresh-macOS test moves to the next new personal Mac.
- A new personal laptop, whenever there is one, follows server B's path: `--profile base` in phase 3 style, then `--profile personal` once the private layer exists.
- `CLAUDE.md` is updated in the same commit whenever a phase changes how the repo is used.

**Local cleanup, outside the repo and any phase**

- Remove the duplicate Anaconda install, most likely the Homebrew cask (`brew uninstall --cask anaconda`), after confirming nothing points at `/opt/homebrew/anaconda3`. This frees several GB.
- Optional: `conda config --set auto_activate_base false`, so `base` activates only on request and stops hiding Homebrew's Python.

## Alternatives considered

Decision: a hand-written installer in plain bash, with zero dependencies. Much of the machinery overlaps with existing dotfile managers, and that is a conscious choice. I want nothing to install before the installer runs, to understand every line, and to enjoy maintaining it.

**How this design compares with chezmoi**, the closest off-the-shelf tool:

| Need | This design | chezmoi |
| --- | --- | --- |
| Dependencies | bash and git, already on every machine | the chezmoi binary (a bootstrap one-liner fetches it) |
| See what would change | `--check`, `--dry-run` | `chezmoi diff`, `chezmoi status`, `apply --dry-run` |
| Per-OS differences | thin wrapper + one platform file per OS (six functions) | templates on `.chezmoi.os`, per-OS ignore rules |
| Profiles | `packages/<profile>.txt` + `shell/profiles/<profile>.sh` | a `profile` value in local config, used by templates |
| PII out of the repo | private layer repo + stub pattern + pre-commit hook | identity in local `chezmoi.toml`, filled in by templates |
| Files that tools edit (`.zshrc`) | local stub that sources the repo file | `create_` prefix, or a managed file plus `chezmoi merge` |
| Files only I edit | symlinks: editing the live file edits the repo | copies by default: `chezmoi re-add` after editing |
| Git-cloned add-ons (Vundle, TPM) | `addons.txt` | `.chezmoiexternal.toml` |
| Packages | platform functions + plain-text lists | `run_onchange_` scripts that I write anyway |
| Backup and undo | timestamped backups, manifest, `--restore` | asks before overwriting; no built-in restore |
| Pull a live file into the repo | `--adopt` | `chezmoi add` |
| Repo file names | plain (`vim/vimrc`) | tool-specific (`dot_vimrc`) |
| Maintenance cost | I own a few hundred lines of bash 3.2 | I own configs and short scripts only |

**Where this design is deliberately different**

- **Zero dependencies.** A fresh machine needs only what ships with it, plus git.
- **Symlinks for files only I edit**, so there is no copy to fall out of step and no `re-add` step.
- **Undo is built in.** Every run can be reversed with `--restore`, which suits the phased rollout.
- **Plain files and plain bash.** The repo reads without knowing any tool's naming rules or template language.

**What I give up:** templating, a mature test suite, and someone else fixing edge cases. The price of owning the tool is that `install.sh` has to stay small and tested, or it rots the way `worksetup.sh` did.

**Ideas borrowed from chezmoi (adopted)**

- `--adopt <file>`, modelled on `chezmoi add`: moves a live file into the repo and links it.
- `addons.txt`, modelled on `.chezmoiexternal.toml`: git-cloned add-ons are declared, not hard-coded. The same idea extends to `links.txt` for managed files.

Both are described in Declared lists and --adopt.

**Other tools, briefly:** GNU stow only creates symlinks and covers none of the OS, profile, PII or package needs. yadm (a bare git repo in `$HOME` with per-OS alternate files) is closer, but it is still a dependency, and it puts `$HOME` itself under git. Nix home-manager is far more than this problem needs.

## Open questions and decisions

The decisions below are settled. The open questions need an answer before the phase shown next to each.

**Decided**

| Decision | Choice | Why |
| --- | --- | --- |
| macOS shell | zsh, with a repo-managed `.zshrc` | macOS default |
| Base tools | git, vim, tmux, curl, wget, glow, taskwarrior, timewarrior, fzf, ripgrep, jq, tree, gh, htop, bat, taskwarrior-tui, taskopen, mosh, iTerm2 (macOS), Vundle, TPM, vim-atom-dark (via Vundle) | tools I need on every machine |
| Files tools edit | local stub + `source`/`include`, not symlink | installers write to `~/.zshrc` directly |
| Machine-specific shell content | below the stub in the local file | conda and others write there anyway |
| Profiles | `personal` and `office` overlays on a shared base | keep work and home apart |
| Public repo | no PII; hook plus review | repo is public on GitHub |
| Linux | Ubuntu/Debian first: two headless servers, 22.04 and 26.04 | what my machines run |
| Linux shell | bash; `~/.bash_aliases` stays local; `shell/bashrc` returns early for non-interactive shells | what the servers use today |
| Git identities | one per account folder under `~/projects/`, on personal machines only; the list with names and emails lives in the private layer; keys are made per machine | keeps accounts apart; personal keys stay off employer hardware |
| Repos | public `dotFiles` for any machine + private `dotFiles-private` layer at `~/.config/dotfiles/private/` on personal machines only | office laptops clone with no login and carry no personal data; personal data is still versioned |
| Commit email | GitHub noreply for accounts with public repos; history left as is; push block turned on last | keeps my real email out of public commit metadata |
| Servers and git identities | same identities as laptops; one key per server per account, generated on the server, never copied | I push and deploy from the servers; per-machine keys can be revoked one at a time |
| conda | stays outside the repo, in local rc files; Anaconda kept on this Mac, Miniconda on server A; never installed on office machines (Miniforge through `cask:miniforge` in `office.txt` if conda is needed); migration to Miniforge deferred to a separate project | a migration touches no dotfiles and risks server A's cron job for no new capability; Anaconda's licence terms are a risk at larger employers |
| Error reporting | numbered steps, echoed commands, one failure block, `--report`, redacted output | the servers have no Claude access |
| Design doc location | `docs/DESIGN.md` in the repo, kept free of PII | one place for everything |
| Installer | hand-written bash, zero dependencies; no chezmoi, stow or yadm | nothing to install first, fully understood, enjoyable to maintain |
| atom-dark colour scheme | from the Vundle plugin only; `.vimrc` uses `silent! colorscheme atom-dark-256` | the separate clone and copy only hid a first-run error (see Current state) |
| Task data | not synced; each machine keeps its own, and Taskwarrior versions may differ | how I use it today |
| taskwarrior-tui, taskopen, gh on Linux | skipped for now (apt `-` in `map.txt`) | taskwarrior-tui and taskopen are not in Ubuntu apt; gh is under review (apt: 2.4.0 on 22.04, too old; 2.46 on 26.04) |
| Rollout order | public part first, proven by real runs on the fresh office Mac and server B; the personal Mac and server A stay read-only until then; server A last | bugs surface where nothing can break |
| Install order | nine-step run order; config linked before plugin installs, files inside plugin folders linked after | plugins read their config to know what to install |
| What the installer manages | declared in `links.txt` and `addons.txt`; `--adopt` adds files | adding a file or add-on is one line, not a code change |
| OS differences | thin `install.sh` wrapper + shared `lib/common.sh` + one small platform file per OS | per-OS scripts would duplicate shared logic and still need bash 3.2 on Mac |

**Open**

- [ ] Before phase 3: gh on Linux. Keep skipping it, install it from apt only where apt is recent enough (26.04), or add GitHub's own apt repo on all servers?
- [ ] Before phase 3: confirm the employer allows Homebrew and open-source CLI tools on the office Mac. It is MDM-managed, so admin rights alone do not settle it. If not allowed, the office Mac uses `--link-only`, and the first real macOS run moves to the next new personal Mac.
