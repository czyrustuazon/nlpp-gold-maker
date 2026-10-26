# Troubleshooting

Problems hit while setting up the gold bake, with the symptom you'll see and the fix.
Setup itself is in the [README](../README.md).

**Where to look first:**

| What | Command / place |
|------|-----------------|
| Failed step output | Actions → the run → **release** job → expand the red step |
| Runner service log | `journalctl -u 'actions.runner.*' -n 50 --no-pager` |
| Detailed job log (paths, env) | `ls -t /opt/nlpp/actions-runner/_diag/Worker_*.log \| head -1` |
| Runner registration | `cat /opt/nlpp/actions-runner/.runner` |
| Runner environment | `cat /opt/nlpp/actions-runner/.env` |

---

## Runner problems

### "There are no runners configured" / runner Offline

- **No runners listed:** the runner isn't registered to *this* repo. Registrations are
  per repo — deleting or recreating the repo orphans the runner; renaming keeps it.
  → [Re-register the runner](#re-register-the-runner).
- **Listed but Offline:** the service is stopped. The service gives up and stops itself
  if it starts before registration exists ("Not configured … stop the service, no
  retry needed"), so start it again after registering:

  ```bash
  cd /opt/nlpp/actions-runner && sudo ./svc.sh start && sudo ./svc.sh status
  ```

### `Cannot configure the runner because it is already configured`

`config.sh` still sees an old registration. Runner **2.337+** stores it in
`.runner_migrated` (older versions: `.runner`), so deleting only `.runner` isn't enough.
If the old repo still exists, unregister properly with `./config.sh remove --token …`.
If it's gone, move the old files aside:

```bash
cd /opt/nlpp/actions-runner
sudo ./svc.sh stop
for f in .runner .runner_migrated .credentials .credentials_rsaparams; do
  [ -e "$f" ] && mv "$f" "$f.old"
done
```

Then register again.

### Service log: `Value cannot be null. (Parameter 'configuredSettings')`

The service is running but the runner has no usable registration (same cause as
above), so it crash-loops every 5 seconds. Stop it, clear the old files, register, start.

### `bash: /opt/nlpp/actions-runner/sudo: No such file or directory` (every job fails instantly)

The **work folder** was set to something other than the default during `config.sh` —
here, `sudo ./svc.sh start` was pasted at the work-folder prompt. The runner put all
job files in a folder with that name, and the space breaks every step's script path.
The `_diag/Worker_*.log` shows it as `Well known directory 'Work': '…/sudo ./svc.sh start'`.

Fix without re-registering — set `workFolder` back to `_work` and restart:

```bash
cd /opt/nlpp/actions-runner
cp .runner .runner.bak
python3 - <<'PY'
import json
raw = open('.runner', 'rb').read()
bom = raw.startswith(b'\xef\xbb\xbf')
d = json.loads(raw.decode('utf-8-sig'))
d['workFolder'] = '_work'
open('.runner', 'wb').write((b'\xef\xbb\xbf' if bom else b'') + json.dumps(d, indent=2).encode())
PY
rm -rf -- "sudo ."          # the junk folder, if that's what was typed
sudo ./svc.sh stop && sudo ./svc.sh start
```

Prevention: press **Enter at every `config.sh` prompt**.

### `$: command not found`

A command was pasted with its leading `$ ` prompt from GitHub's instructions.
Paste only what follows the `$ `.

### Don't use `./run.sh`

`run.sh` runs the runner in the foreground and dies when SSH closes. The service
(`svc.sh install` / `start`) does the same job in the background and survives reboots.

### `sudo: interactive authentication is required` / `a terminal is required`

sudo needs your password, which needs a terminal. From PowerShell use `ssh -t`:

```powershell
ssh -t you@your-server "cd /opt/nlpp/actions-runner && sudo ./svc.sh start"
```

### Re-register the runner

For a new or recreated repo, a broken config, or a moved runner:

1. Get a fresh token: `https://github.com/OWNER/nlpp-gold-maker/settings/actions/runners/new`
   (Linux / x64; copy only the `--token` value; expires in ~1 hour).
2. On the server:

   ```bash
   cd /opt/nlpp/actions-runner
   sudo ./svc.sh stop
   sudo ./svc.sh uninstall
   for f in .runner .runner_migrated .credentials .credentials_rsaparams; do
     [ -e "$f" ] && mv "$f" "$f.old"
   done
   ./config.sh --url https://github.com/OWNER/nlpp-gold-maker --token PASTE_TOKEN
   sudo ./svc.sh install
   sudo ./svc.sh start
   sudo ./svc.sh status
   ```

   Press Enter at every `config.sh` prompt; answer **Y** if asked to replace an
   existing runner with the same name. `.env` is not touched and carries over.

---

## Workflow step failures

### Check vanilla inputs: `NLPP_VANILLA_… not set` or `missing file`

- **not set:** the variable isn't in `/opt/nlpp/actions-runner/.env` (and no repo
  variable overrides it), or the runner wasn't restarted after editing `.env`.
- **missing file:** the path in `.env` is wrong or the file wasn't copied.
  `ls -lh` the path on the server.

### Check vanilla inputs: `VANILLA CHECK FAILED` / `Vanilla files do not match`

One or more files on the runner aren't the unpatched originals listed in
[`vanilla.sha256`](../vanilla.sha256). The log and the run summary show actual vs
expected for each file. A patched file bakes without any error but produces a wrong,
double-patched Release — which is why this check fails hard.

Seen in practice: an old `extracted\romfs\` whose `img.bin` and
`textresource_resident_jpn.trb` had been patched in place (same size, different
hash). Fix: re-copy from EngPatcher's `cache\vanilla_from_rom\` (extracted straight
from the ROM) — commands in README setup step 2.

If you intentionally use a different dump or game revision, replace the hashes in
`vanilla.sha256` with yours (`sha256sum` on the server) and commit.

### `missing vanilla textresource_config.trb next to …/textresource_jpn.trb`

`deploy_name_kanji_trb.py` reads `textresource_config.trb` from the same folder as
`NLPP_VANILLA_TRB`. Copy it there (README setup step 2). The vanilla check now
catches this before the bake.

`NLPP_VANILLA_CODE` is easy to miss: the bake always builds
`release/name_input_code.bin` from vanilla `code.bin`, and a fresh EngPatcher clone has
no `code.bin` to fall back on. Without it the bake fails with
`vanilla exefs/code.bin not found`.

### Install Python deps: `No such file or directory: 'requirements.txt'`

EngPatcher commit `c42db0b` moved `requirements.txt` to `dev/requirements.txt`. The
workflow uses `dev/requirements.txt` when present and falls back to the root file for
older refs. If you see this, the workflow on this repo is out of date.

### `error: externally-managed-environment`

Ubuntu 23.04+ blocks `pip install` into system Python (PEP 668). The workflow installs
into a venv (`.venv` in the job workspace); make sure `python3-venv` is installed.

### Publish GitHub Release: `gh: command not found`

Install the GitHub CLI on the server. If `apt-get install gh` finds nothing, add
GitHub's apt repo first:

```bash
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list
sudo apt-get update && sudo apt-get install -y gh
```

### skip_pack run fails at "Fetch previous bake"

skip_pack downloads the previous Release to build on. On the first run there isn't one —
run once **without** skip_pack.

### Manual run shows as skipped

Manual runs only execute for the repo owner. Other accounts get a skipped job by design.

### Can't find the "Run workflow" button

Actions → click **Release gold bake** in the left sidebar (not "All workflows"). The
button is on the right of the blue *"This workflow has a workflow_dispatch event
trigger"* banner.

---

## EngPatcher → dispatch problems

### Request gold Release: `Missing EngPatcher secret NLPP_GOLD_DISPATCH_TOKEN`

Add the secret on **EngPatcher** (not this repo): Settings → Secrets and variables →
Actions → New repository secret. See README setup step 6.

### `repository_dispatch failed` (403 / 404)

- **403:** the token lacks **Contents: Read and write** on `nlpp-gold-maker`, or has expired.
- **404:** wrong target repo, or the token can't see it. Check the EngPatcher variable
  `NLPP_GOLD_REPO` (delete it if this repo is `OWNER/nlpp-gold-maker`), and that the
  token's repository access includes this repo.

### Push to EngPatcher didn't start a bake

Only pushes to EngPatcher **`main`** dispatch. Check EngPatcher's Actions tab for the
**Request gold Release** run first; if it's green, look for the run here.

---

## Users can't download the bake

- The Release must be on a **public** repo — private-repo Releases 404 without a token,
  and `fetch_release_bake.py` then falls back to a multi-hour local rebuild.
- The tool looks for `<owner>/nlpp-gold-maker` by default. Any other name needs
  `--repo OWNER/REPO` or `NLPP_GITHUB_REPO`.

---

## Local-machine notes (Windows)

- If `git fetch` / `push` from a script or another shell says `Permission denied
  (publickey)`, that shell can't see your SSH agent. Use the shell or editor you
  normally push from.
- Piping a script from PowerShell to `ssh … bash` adds a UTF-8 byte-order mark and
  the first command fails (`$'\357\273\277cd': command not found`). Run commands
  inline or copy the script to the server first.
