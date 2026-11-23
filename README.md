# local-git

The fleet's private git hub: bare repos on macpro at `/srv/git/<name>.git`,
reached over SSH on the tailnet (`macpro:/srv/git/<name>.git`). No daemon, no
web UI, no extra users. Repos are owned by `jacob`, and every machine pushes and
fetches as `jacob` over SSH.

Machines push commits to the hub and workers fetch from it (jacob-compute-mng
PLAN.md, "Code"). macpro's nightly restic backup already includes `/srv/git`
(jacob-compute-mng `fleet.ini`, `backup =`), so nothing here handles backups.

## Repos on the hub

`repos.txt` lists them. `bin/lgit check` compares that list against
`/srv/git`.

## Usage

```sh
bin/lgit ls                      # repos on the hub, with size and HEAD branch
bin/lgit new <name> [desc]       # create /srv/git/<name>.git (bare, HEAD=main)
bin/lgit add [dir] [name]        # in a local clone: add remote `hub`, push all branches and tags
bin/lgit clone <name> [dir]      # clone from the hub (remote named `hub`)
bin/lgit check                   # repos.txt vs. what is actually on macpro
```

Set `LGIT_HOST` (default `macpro`) and `LGIT_ROOT` (default `/srv/git`) to point
somewhere else.
