#!/usr/bin/env bash
# CD: run by the hub's hook on main after ci/test.sh passes. Deploys onto macpro itself:
#   ~/apps/$APP/releases/<commit>/   one folder per deploy (last 5 kept)
#   ~/apps/$APP/current              symlink to the live release
#   systemd user service $APP        $START, with PORT and APP_VERSION in its environment
# Rollback: point `current` at an older release and `systemctl --user restart $APP`.
#
# Template from local-git/examples: copy to <project>/ci/deploy.sh and edit these three.
# The app must answer GET / on $PORT with a body containing APP_VERSION (the health check).
set -euo pipefail
APP=test-project                 # service and folder name
PORT=8200                        # pick a free port: ssh macpro ss -ltn
START="/usr/bin/python3 hello.py"   # command run from the release folder
base=~/apps/$APP rel=~/apps/$APP/releases/$CI_COMMIT
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}   # for systemctl --user

mkdir -p "$base/releases"
rm -rf "$rel" && cp -a . "$rel"
ln -sfn "$rel" "$base/current"

mkdir -p ~/.config/systemd/user
cat > ~/.config/systemd/user/$APP.service <<UNIT
[Unit]
Description=$APP (deployed by the hub CI hook)

[Service]
WorkingDirectory=$base/current
Environment=PORT=$PORT APP_VERSION=${CI_COMMIT:0:7}
ExecStart=$START
Restart=on-failure

[Install]
WantedBy=default.target
UNIT
systemctl --user daemon-reload
systemctl --user enable -q $APP
systemctl --user restart $APP

# health check: the new version must answer
for _ in $(seq 20); do
  if curl -sf localhost:$PORT | grep -q "${CI_COMMIT:0:7}"; then echo "deployed ${CI_COMMIT:0:7}: $(curl -s localhost:$PORT)"; break; fi
  sleep 0.5
done
curl -sf localhost:$PORT | grep -q "${CI_COMMIT:0:7}" || { echo "health check failed"; systemctl --user status $APP --no-pager; exit 1; }

# keep the 5 newest releases, never the live one
ls -1t "$base/releases" | tail -n +6 | while read -r old; do
  [[ $(readlink -f "$base/current") == "$base/releases/$old" ]] || rm -rf "$base/releases/$old"
done
