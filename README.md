# local-git

The fleet's private git hub: bare repos on macpro at `/srv/git/<name>.git`,
used as an ordinary SSH git remote (`macpro:/srv/git/<name>.git`). There is no
daemon, web UI or extra user. Each machine pushes and fetches as `jacob` over SSH.

This repo holds:

- `bin/lgit`: a small client-side helper to list, create, clone and check hub repos
- `repos.txt`: the list of repos that should exist on the hub

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
- **Remote name:** the convention is `hub` (`lgit clone` uses it), so `origin` can stay GitHub for
  repos that live in both places.
- **Backups:** macpro's nightly restic backup includes `/srv/git`
  (jacob-compute-mng `fleet.ini`, `backup =`), so nothing here handles backups.

## Install

```sh
git clone https://github.com/photon-cat/local-git ~/projects/local-git
ln -s ~/projects/local-git/bin/lgit ~/.local/bin/lgit     # any dir on PATH
```

Requirements: git, and key-based SSH to `macpro` as `jacob`. lgit follows the
symlink back to this checkout to find `repos.txt`, so `git pull` here updates
the command.

## Usage

```sh
lgit ls                      # repos on the hub, with size and default branch
lgit new <name> [desc]       # create /srv/git/<name>.git (bare, HEAD=main), add to repos.txt,
                             #   print the git commands to connect a local repo
lgit clone <name> [dir]      # clone from the hub, remote named `hub`
lgit check                   # repos.txt vs. what is on the hub; exits 1 if they differ
```

`lgit` with no arguments prints this list. `new` appends to `repos.txt`;
commit that change here afterwards.

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

## Without lgit

lgit is a convenience; connecting and pushing is always plain git. Creating
the repo is one `ssh` command, the only step git can't do over SSH:

```sh
ssh macpro 'git init --bare -b main /srv/git/foo.git'
git remote add hub macpro:/srv/git/foo.git
git push -u hub main
git clone -o hub macpro:/srv/git/foo.git    # on another machine
```

Add the name to `repos.txt` if you want `lgit check` to stay accurate.

## Moving the hub to another box

```sh
ssh newbox 'sudo apt-get install -y git && sudo mkdir -p /srv/git && sudo chown jacob:jacob /srv/git'
ssh macpro 'rsync -a /srv/git/ newbox:/srv/git/'
LGIT_HOST=newbox lgit check
git remote set-url hub newbox:/srv/git/<name>.git     # in each clone
```

Also add `/srv/git` to the new box's `backup =` line in `fleet.ini`.

## Limits

- No Git LFS. Keep large binaries and datasets in jacob-compute-mng's object
  store (`/srv/store`), not in git.
- `/srv/git` is on macpro's SSD, which is nearly full; watch it if large repos
  are added.
- No `git gc` schedule, no hooks, and no per-user access control: anyone who
  can ssh to macpro as `jacob` can read and write every repo.
- Deleting or renaming a hub repo is manual (`ssh macpro rm -rf /srv/git/x.git`),
  followed by an edit to `repos.txt`.
