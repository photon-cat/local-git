# local-git

The fleet's private git hub: bare repos on macpro at `/srv/git/<name>.git`,
used as an ordinary SSH git remote (`macpro:/srv/git/<name>.git`). There is no
daemon, web UI or extra user. Each machine pushes and fetches as `jacob` over SSH.

This repo holds `bin/lgit`, a small client-side helper to list, create and
clone hub repos, and `hooks/post-receive`, an optional CI/CD hook. The hub
itself is the only record of which repos exist.

## How it works

- **The hub** is a plain folder, `/srv/git` on macpro (internal SSD, owned by
  `jacob`), with one *bare* repo per project. A bare repo has git's data
  (objects, refs) but no checked-out files, which is why anyone can push to any
  branch of it.
- **The remote** `macpro:/srv/git/foo.git` means "ssh to `macpro`, use the repo
  at this path". `macpro` resolves through Tailscale MagicDNS
  (`macpro.tail746d21.ts.net`, `100.114.105.46`), so it works wherever the
  machine is on the tailnet.
- **On fetch or push** git runs `ssh macpro git-upload-pack` or
  `git-receive-pack` for the length of the command. Only missing objects are
  sent, as one compressed pack. Nothing stays running on macpro.
- **lgit runs on your machine, not on macpro.** Each command either runs plain
  shell or git over `ssh macpro`, or runs ordinary git against the remote.
  macpro needs only sshd, git and the `/srv/git` folder.
- **Remote name:** the convention is `hub` (`lgit clone` uses it), so `origin`
  can stay GitHub for repos that live in both places.
- **Backups:** macpro's nightly restic backup includes `/srv/git`
  (jacob-compute-mng `fleet.ini`, `backup =`), so nothing here handles backups.

## Install

```sh
git clone https://github.com/photon-cat/local-git ~/projects/local-git
ln -s ~/projects/local-git/bin/lgit ~/.local/bin/lgit     # any dir on PATH
```

Requirements: git, and key-based SSH to `macpro` as `jacob`. Because it's a
symlink, `git pull` here updates the command.

## Usage

```sh
lgit ls                      # repos on the hub, with size and default branch
lgit new <name>              # create /srv/git/<name>.git (bare, HEAD=main) and print
                             #   the git command to connect a local repo to it
lgit clone <name> [dir]      # clone from the hub, remote named `hub`
lgit ci <name>               # install/update the CI/CD hook in that hub repo
lgit log <name> [commit]     # last CI runs, then the newest (or that commit's) log
```

`lgit` with no arguments prints a one-line usage.

Environment variables:

| Variable    | Default    | Meaning                        |
|-------------|------------|--------------------------------|
| `LGIT_HOST` | `macpro`   | ssh host of the hub            |
| `LGIT_ROOT` | `/srv/git` | folder of bare repos on the hub |

### New project, pushed to the hub

```sh
mkdir ~/projects/foo && cd ~/projects/foo
git init -b main && echo "# foo" > README.md && git add . && git commit -m "Initial commit"
lgit new foo                 # creates macpro:/srv/git/foo.git
git remote add hub macpro:/srv/git/foo.git
git push -u hub main         # -u: plain `git push` / `git pull` now use the hub
```

### Existing repo already on the hub

```sh
git remote add hub macpro:/srv/git/gnsswire.git && git fetch hub
git log hub/main..main       # compare histories before pushing
```

## CI/CD

`lgit ci <name>` installs `hooks/post-receive` into `/srv/git/<name>.git/hooks/`.
After that, every push to the hub:

1. exports the pushed commit into a fresh temp folder on macpro,
2. runs the repo's `ci/test.sh` (CI); a commit without one is skipped,
3. on `main`, if the tests passed and `ci/deploy.sh` exists, runs it (CD).

The run is in the background, so `git push` returns at once and prints
`remote: ci: <sha> on <branch> queued`. Runs are one at a time per repo, as
`jacob`, with `CI_REPO`, `CI_BRANCH` and `CI_COMMIT` set. Results:

- `/srv/git/<name>.git/ci/<commit>.log`: full output (`lgit log <name>`)
- `/srv/git/<name>.git/ci/runs`: one line per run, `ok` or `FAILED in test|deploy`
- an ntfy alert to the URL in macpro's `~/.config/cm/notify`, if present

The pipeline lives in each project, not here. A deploy can do anything
`jacob` can on macpro, such as restart a systemd user service (lingering is on
for `jacob`, so those run without a login) or rsync and ssh to another box.

`examples/ci/` is a template to copy into a project and edit, not shared code,
so each project keeps its pipeline in its own history:

- `test.sh`: runs the tests (here `python3 -m unittest`; swap in your own)
- `deploy.sh`: runs the app on macpro as a systemd user service, with a release
  folder per commit, a `current` symlink, a health check and the 5 newest
  releases kept. Set `APP`, `PORT` and `START` at the top.

```sh
cp -r ~/projects/local-git/examples/ci ./ci     # then edit ci/deploy.sh
lgit ci <name>                                  # once per hub repo
git add ci && git commit -m "CI" && git push
```

`test-project` on the hub uses this template.

Re-run a commit without pushing:

```sh
ssh macpro 'cd /srv/git/<name>.git && echo "- <sha> refs/heads/main" | hooks/post-receive'
```

After editing `hooks/post-receive`, run `lgit ci <name>` again for each repo
that uses it.

## Without lgit

lgit is a convenience; connecting and pushing is always plain git. Creating
the repo is one `ssh` command, the only step git can't do over SSH:

```sh
ssh macpro 'git init --bare -b main /srv/git/foo.git'
git remote add hub macpro:/srv/git/foo.git
git push -u hub main
git clone -o hub macpro:/srv/git/foo.git    # on another machine
```

## Moving the hub to another box

```sh
ssh newbox 'sudo apt-get install -y git && sudo mkdir -p /srv/git && sudo chown jacob:jacob /srv/git'
ssh macpro 'rsync -a /srv/git/ newbox:/srv/git/'
LGIT_HOST=newbox lgit ls
git remote set-url hub newbox:/srv/git/<name>.git     # in each clone
```

Also add `/srv/git` to the new box's `backup =` line in `fleet.ini`.

## Limits

- No Git LFS. Keep large binaries and datasets in jacob-compute-mng's object
  store (`/srv/store`), not in git.
- `/srv/git` is on macpro's SSD, which is nearly full; watch it if large repos
  are added.
- No `git gc` schedule and no per-user access control: anyone who can ssh to
  macpro as `jacob` can read and write every repo.
- CI runs unsandboxed as `jacob` on macpro, so only enable it on your own repos.
  There's no web UI or commit status; old logs in `ci/` aren't pruned.
- Deleting or renaming a hub repo is manual: `ssh macpro rm -rf /srv/git/x.git`
  or `ssh macpro mv /srv/git/x.git /srv/git/y.git`.
