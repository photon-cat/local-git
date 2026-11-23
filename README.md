# local-git

A self-hosted git hub with no server software: bare repos in a folder on any
machine you can SSH into, used as ordinary git remotes, plus optional CI/CD that
runs on that machine when you push.

- `bin/lgit`: small client command to list, create and clone hub repos and
  install the CI hook
- `hooks/post-receive`: the CI/CD hook
- `examples/ci/`: a test and deploy template to copy into a project

## Setup

On the hub (any Linux/macOS box with sshd and git):

```sh
sudo mkdir -p /srv/git && sudo chown "$USER" /srv/git
```

On each client:

```sh
git clone https://github.com/photon-cat/local-git ~/projects/local-git
ln -s ~/projects/local-git/bin/lgit ~/.local/bin/lgit      # any dir on PATH

mkdir -p ~/.config/lgit && cat > ~/.config/lgit/config <<'EOF'
LGIT_HOST=myserver        # ssh host of the hub (required)
LGIT_USER=me              # ssh user (optional; default: what ssh would use)
LGIT_ROOT=/srv/git        # repo folder on the hub (optional; this is the default)
EOF
```

Environment variables with the same names override the file. Clients need
key-based SSH to the hub.

## Usage

```sh
lgit ls                      # repos on the hub: name, size, default branch
lgit new <name>              # create <root>/<name>.git (bare, default branch main)
lgit clone <name> [dir]      # clone it, with the remote named `hub`
lgit ci <name>               # install/update the CI/CD hook in that repo
lgit log <name> [commit]     # recent CI runs and the latest (or that commit's) log
```

lgit never pushes or edits remotes. To put an existing project on the hub:

```sh
lgit new foo
git remote add hub me@myserver:/srv/git/foo.git
git push -u hub main
```

Without lgit, the same thing is `ssh me@myserver git init --bare -b main /srv/git/foo.git`
and plain git. The hub is a normal SSH remote: git runs `git-upload-pack` or
`git-receive-pack` over ssh for each fetch or push, and nothing stays running.

## CI/CD

After `lgit ci <name>`, every push to that repo, in the background on the hub:

1. exports the pushed commit to a temp folder,
2. runs `ci/test.sh` if the commit has one,
3. on `main`, if tests passed, runs `ci/deploy.sh` if present.

Runs are one at a time per repo, as the hub's SSH user, with `CI_REPO`,
`CI_BRANCH` and `CI_COMMIT` set. Output goes to `<repo>.git/ci/<commit>.log`
and a summary line to `<repo>.git/ci/runs` (`lgit log <name>`). For alerts, set
a URL on the hub, e.g. an ntfy.sh topic; the result is POSTed to it:

```sh
ssh me@myserver git config --global lgit.notify https://ntfy.sh/my-topic
```

To start a project from the template (tests, then deploy as a systemd user
service on the hub with a release folder per commit, a health check and
rollback; set `APP`, `PORT`, `START` at the top of `deploy.sh`):

```sh
cp -r ~/projects/local-git/examples/ci ./ci
lgit ci foo
git add ci && git commit -m "CI" && git push
```

Deploying somewhere else is just a different `deploy.sh`, e.g. rsync and ssh to
a server.

## Limits

- One SSH user for everyone: no per-repo permissions, no web UI, no LFS.
- CI runs unsandboxed on the hub; only enable it on repos you trust.
- No `git gc` schedule; old CI logs aren't pruned. Back up the repo folder.
