# nlpp-gold-maker

Publishes **`bake_img.bin`** + **`name_input_code.bin`** + **`romfs_overlay.zip`** for
[NewLovePlusPlusEngPatcher](https://github.com/czyrustuazon/NewLovePlusPlusEngPatcher)
users. You edit EngPatcher; this repo only runs the Ubuntu bake and hosts the public
Releases that EngPatcher's Drop CIA `.bat` downloads.

```text
  push / merge → EngPatcher main
        → EngPatcher "Request gold Release" workflow (GitHub-hosted)
        → repository_dispatch → this repo
        → "Release gold bake" on your self-hosted Ubuntu runner
        → if Release "gold" already has bake_img.bin, download it
             (full PNG pack only when missing, image inputs changed, or force_pack)
             (name_input_code.bin missing on that Release → rebuild only that file)
        → Release tag "gold" (assets replaced each run)
        → users: python tools/fetch_release_bake.py --tag gold
```

Other EngPatcher branches do nothing. A from-scratch PNG pack can take many hours.
CIA / drop-bat patching stays on **Windows**.

**Keep this repo named `nlpp-gold-maker` and public.** EngPatcher's
`fetch_release_bake.py` and its dispatch workflow both default to
`<owner>/nlpp-gold-maker`, and Releases on a private repo can't be downloaded
without a token. Any other name works only if every user sets `NLPP_GITHUB_REPO`.

Something broken? See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

---

## How it works

| Piece | Where | Job |
|-------|-------|-----|
| `request-gold-release.yml` | EngPatcher, GitHub-hosted runner | On push to `main`, POSTs a `repository_dispatch` here using secret `NLPP_GOLD_DISPATCH_TOKEN` |
| [`release.yml`](.github/workflows/release.yml) | This repo, **your** self-hosted runner | Clones EngPatcher, installs deps into a venv, runs `tools/rebuild_bake_img.py`, zips the overlay, publishes Release `gold` with `gh` |
| Runner `.env` | `/opt/nlpp/actions-runner/.env` on the server | Tells the bake where the vanilla game files are |
| Vanilla files | `/opt/nlpp/vanilla/` on the server | Your own dump — never committed or published |

Workflow triggers:

- `repository_dispatch` (`engpatcher-release`) from EngPatcher — needs the dispatch token.
- `workflow_dispatch` (Run workflow button) — **repo owner only**; other actors are skipped.
- No `pull_request` trigger, by design (see [Security](#security)).

Run inputs (manual) / payload (dispatch): `skip_pack`, `tag_name` (`gold` or `vX.Y.Z`),
`workers`, `engpatcher_ref`.

---

## Setup (one-time)

**You need:** an Ubuntu **x86_64** box (not Pi / ARM), SSH to it (Tailscale is fine),
sudo on it, and a vanilla New Love Plus+ extract (RomFS + ExeFS) on your PC.

> **Copying commands:** GitHub's runner page and many docs show commands with a
> leading `$ `. That is the prompt, not part of the command — never paste it
> (`$: command not found`). Every command block in this README is paste-ready.

### 1. Server folders + packages

```bash
git clone https://github.com/OWNER/nlpp-gold-maker.git ~/nlpp-gold-maker
cd ~/nlpp-gold-maker
sudo bash scripts/prepare-runner-dirs.sh /opt/nlpp
sudo chown -R "$USER:$USER" /opt/nlpp
sudo apt-get update
sudo apt-get install -y python3 python3-venv python3-pip zip git gh
```

This creates `/opt/nlpp/vanilla/{romfs,exefs}`, `/opt/nlpp/actions-runner`,
`/opt/nlpp/cache/img_pack`. The `chown` means you won't need sudo to copy files in.

- `gh` (GitHub CLI) publishes the Release. If `apt` can't find it, add GitHub's apt
  repo first — see [Troubleshooting](docs/TROUBLESHOOTING.md#publish-github-release-gh-command-not-found).
- `python3-venv` is required: Ubuntu 23.04+ refuses system-wide `pip install`
  (PEP 668), so the workflow builds a venv each run.

### 2. Copy vanilla files from your PC

Use the **vanilla** extract — **not** EngPatcher's `release/` folder, and not any
`code.bin` under `out/`, `ab_test/` or a `luma/` mods folder (those are patched).

| File on your PC (`...\extracted\`) | On the server |
|------|-----------|
| `romfs\img.bin` | `/opt/nlpp/vanilla/romfs/img.bin` |
| `romfs\SystemData\TextResource\textresource_jpn.trb` | `/opt/nlpp/vanilla/romfs/SystemData/TextResource/` |
| `romfs\SystemData\TextResource\textresource_resident_jpn.trb` | `/opt/nlpp/vanilla/romfs/SystemData/TextResource/` |
| `romfs\SystemData\TextResource\textresource_config.trb` | `/opt/nlpp/vanilla/romfs/SystemData/TextResource/` |
| `exefs\code.bin` (or `code.bin.bak` if present) | `/opt/nlpp/vanilla/exefs/code.bin` |

All five are **required**. `code.bin` is patched into `release/name_input_code.bin`;
`textresource_config.trb` is read from the same folder as `textresource_jpn.trb`.

**Best source:** EngPatcher's `cache\vanilla_from_rom\`, extracted straight from your
`.3ds`/`.cia` (`python tools/rebuild_bake_img.py --rom …` creates it). Older extract
folders can hold files that were patched in place and still look "vanilla".

Every run checks all five against [`vanilla.sha256`](vanilla.sha256) and **fails before
the bake starts** if any hash differs — see the **Check vanilla inputs** step and the
run summary table. For a different dump or game revision, update that file.

From **PowerShell** on your PC:

```powershell
$server = "you@your-server"      # SSH user@host (Tailscale MagicDNS name or 100.x.x.x)
$x = "C:\path\to\NewLovePlusPlusEngPatcher\cache\vanilla_from_rom"
$tr = "SystemData\TextResource"

scp "$x\romfs\img.bin" "${server}:/opt/nlpp/vanilla/romfs/img.bin"
scp "$x\romfs\$tr\textresource_jpn.trb" "$x\romfs\$tr\textresource_resident_jpn.trb" "$x\romfs\$tr\textresource_config.trb" "${server}:/opt/nlpp/vanilla/romfs/SystemData/TextResource/"
scp "$x\exefs\code.bin" "${server}:/opt/nlpp/vanilla/exefs/code.bin"
```

Check against the expected hashes before running anything:

```powershell
ssh $server "sha256sum /opt/nlpp/vanilla/romfs/img.bin /opt/nlpp/vanilla/exefs/code.bin /opt/nlpp/vanilla/romfs/SystemData/TextResource/*.trb"
```

Compare with [`vanilla.sha256`](vanilla.sha256).

### 3. Runner environment

Copy [`.env.example`](.env.example) to `/opt/nlpp/actions-runner/.env`
(on the server, from the repo clone):

```bash
grep '^NLPP_' .env.example >> /opt/nlpp/actions-runner/.env
cat /opt/nlpp/actions-runner/.env
```

It must end up containing:

```bash
NLPP_VANILLA_IMG=/opt/nlpp/vanilla/romfs/img.bin
NLPP_VANILLA_CODE=/opt/nlpp/vanilla/exefs/code.bin
NLPP_VANILLA_TRB=/opt/nlpp/vanilla/romfs/SystemData/TextResource/textresource_jpn.trb
NLPP_VANILLA_RESIDENT_TRB=/opt/nlpp/vanilla/romfs/SystemData/TextResource/textresource_resident_jpn.trb
NLPP_PACK_CACHE=/opt/nlpp/cache/img_pack
```

The runner reads `.env` only when it starts — restart it after any edit (step 4).
Repo **variables** with the same names override `.env` if you set them.

### 4. Register the self-hosted runner

1. Open `https://github.com/OWNER/nlpp-gold-maker/settings/actions/runners/new`,
   choose **Linux / x64**.
2. On the server, download and unpack the runner using the `curl` / `tar` lines from
   that page (skip if `/opt/nlpp/actions-runner/config.sh` already exists):

   ```bash
   cd /opt/nlpp/actions-runner
   # paste the curl … and tar xzf … lines from the GitHub page here (without the "$ ")
   ```

3. Register it with the token from that page (it expires after about an hour):

   ```bash
   cd /opt/nlpp/actions-runner
   ./config.sh --url https://github.com/OWNER/nlpp-gold-maker --token PASTE_TOKEN
   ```

   - Run `config.sh` **without** sudo — it refuses to run as root.
   - It asks four questions: runner group, runner name, labels, **work folder**.
     **Press Enter at every prompt** to accept the defaults. Don't type or paste
     anything else — whatever you type at the work-folder prompt becomes a folder
     name, and a name with a space in it breaks every job.
   - Success ends with **`Settings Saved.`**

4. Install it as a service and start it:

   ```bash
   sudo ./svc.sh install
   sudo ./svc.sh start
   sudo ./svc.sh status
   ```

   Use the service — **not** `./run.sh`, which stops when you close SSH.
   `status` should say `active (running)`, and the runners page should show the
   runner as **Idle**. Confirm it connected:

   ```bash
   journalctl -u 'actions.runner.*' -n 20 --no-pager    # look for "Listening for Jobs"
   ```

To register again later (new repo, renamed repo, broken config), follow
[Re-register the runner](docs/TROUBLESHOOTING.md#re-register-the-runner).

### 5. Lock down fork pull requests

This repo is public and its runner is your server. Open
`https://github.com/OWNER/nlpp-gold-maker/settings/actions` →
**Approval for running fork pull request workflows from contributors** →
**Require approval for all external contributors**. See [Security](#security).

### 6. Wire EngPatcher → this repo

**Create the dispatch token** at <https://github.com/settings/personal-access-tokens/new>
(fine-grained):

| Field | Value |
|-------|-------|
| Token name | `nlpp-gold-dispatch` |
| Expiration | your choice — when it expires, pushes stop triggering bakes |
| Resource owner | the account that owns this repo |
| Repository access | **Only select repositories** → `nlpp-gold-maker` |
| Repository permissions | **Contents: Read and write** (Metadata: Read is added automatically) |

Copy the `github_pat_…` value — GitHub shows it once.

**On EngPatcher** → Settings → Secrets and variables → Actions:

- **Secrets** → New repository secret: `NLPP_GOLD_DISPATCH_TOKEN` = the token.
- **Variables**: `NLPP_GOLD_REPO` is only needed if this repo is *not*
  `OWNER/nlpp-gold-maker`. Delete any stale value pointing somewhere else.
- `.github/workflows/request-gold-release.yml` must be on EngPatcher `main`.

**Optional, on this repo:**

| Kind | Name | Purpose |
|------|------|---------|
| Secret | `ENGPATCHER_CHECKOUT_TOKEN` | Only if EngPatcher is private (contents:read) |
| Secret | `NLPP_PROGRESS_ENDPOINT`, `NLPP_PROGRESS_TOKEN` | Companion-site progress bar; step is skipped if unset |
| Secret | `DISCORD_WEBHOOK_URL` | Posts to Discord when a bake starts building, deletes the old Release, and finishes (success/failure/cancelled), plus smoke job status; steps skip if unset |
| Variable | `NLPP_PACK_WORKERS` | PNG pack workers (default 2) |
| Variable | `NLPP_ENGPATCHER_REPO` | Default `OWNER/NewLovePlusPlusEngPatcher` |
| Variable | `NLPP_ENGPATCHER_REF` | Default `main` |
| Variable | `FORCE_SKIP_PACK` | `true` forces every run to skip the pack |
| Variable | `NLPP_VANILLA_*`, `NLPP_PACK_CACHE` | Override the runner `.env` paths |

**code.bin gates.** Before touching the Release, the bake runs EngPatcher's
`tests/test_code_patch_map.py` against `NLPP_VANILLA_CODE`; after the bake,
`name_input_code.bin` must match the hash committed in EngPatcher
`tests/snapshots/code_patch_map.json`. A wrong vanilla dump fails here too
(expected sha256 `a83d349d0a000a127f93f743c038921903a2aae111b4b9005aadd446324ab890`),
so use the untouched `code.bin.bak` if your extract has one.

### 7. Azahar smoke boot (optional)

`.github/workflows/smoke.yml` boots each published gold bake in
[azahar-3ds-accurate](https://github.com/czyrustuazon/azahar-3ds-accurate)
under Xvfb + software OpenGL and fails if the game data-aborts. That fork
replays three real hardware crashes; a build that lost its guard goes red. It
never blocks or edits the Release.

```bash
# Docker build of the fork's main. 1-3 hours on a 2-core laptop.
# Re-run after pushing changes to the fork.
sudo bash scripts/setup-smoke-runner.sh
# If Azahar is already built, ensure host libraries are installed:
sudo apt-get install -y libopengl0 libfontconfig1 libharfbuzz0b
```

Then copy from your PC:

| What | On server |
|------|-----------|
| Decrypted New Love Plus+ `.3ds` / `.cci` | `/opt/nlpp/vanilla/rom.3ds` |
| `sdmc/` and `nand/` from an Azahar user folder with a title save (e.g. EngPatcher `ab_test/azahar_instances/a/user/`) | `/opt/nlpp/smoke/seed_user/` |

Without a save the game sits on its create-save prompt and the crash sites are
never reached. Add the three `NLPP_SMOKE_*` / `NLPP_ROM` lines from
[`.env.example`](.env.example) to the runner `.env` and restart it. Until then
the smoke job logs a notice and passes.

Keep the laptop awake with the lid shut: set `HandleLidSwitch=ignore` in
`/etc/systemd/logind.conf`, then `sudo systemctl restart systemd-logind`.

---

## Testing the setup

Do these in order; each one proves one more link in the chain.

1. **Runner online** — Settings → Actions → Runners shows the runner as **Idle**.
2. **First full bake (manual)** — Actions → click **Release gold bake** in the left
   sidebar → **Run workflow** (button in the blue banner) → leave **skip_pack
   unticked** → Run workflow. There is no `gold` Release yet, so a skip_pack run
   would fail. Watch the first steps:
   - **Clone EngPatcher** → EngPatcher reachable
   - **Set up Python venv** / **Install Python deps** → Python OK
   - **Check vanilla inputs** → all five files `OK` against `vanilla.sha256`
     (table in the run summary) → `.env` loaded and files are unpatched

   **Rebuild gold bake** then runs for hours; you can close the browser. At the end
   **Publish GitHub Release** creates `…/releases/tag/gold` with both files.
3. **Quick re-run** — once `gold` exists, Run workflow with **skip_pack ticked**;
   finishes in minutes.
4. **Dispatch** — push any commit to EngPatcher `main`. On EngPatcher, **Request gold
   Release** goes green ("Pinged OWNER/nlpp-gold-maker"), and a new **Release gold
   bake** run appears here within seconds (a full bake; cancel it if you don't want one).
5. **Public download** — from an EngPatcher clone, signed out / on another machine:
   `python tools/fetch_release_bake.py --tag gold` downloads both files without a token.

Watch a running bake from your PC:

```powershell
ssh you@your-server "journalctl -u 'actions.runner.*' -f"
```

---

## Security

GitHub warns against self-hosted runners on public repos because a `pull_request`
workflow runs the **PR's** copy of the workflow file — a fork could add a job that
runs on your server. This setup avoids that:

- `release.yml` has **no `pull_request` trigger**. Don't add one.
- Fork-PR approval is set to **all external contributors** (setup step 5), so nothing
  from a fork runs without you approving it. Never approve a PR that touches
  `.github/workflows/`.
- Manual runs are limited to the repo owner (`github.actor == github.repository_owner`).
- Dispatches need `NLPP_GOLD_DISPATCH_TOKEN`, which lives only as an EngPatcher
  secret. Anyone with write access to EngPatcher `main` can trigger a bake by pushing.
- Don't give write access on this repo to anyone you wouldn't trust on your server.

---

## Using the bake (EngPatcher users)

From an EngPatcher clone (any OS):

```bash
python tools/fetch_release_bake.py --tag gold
# other repo name: --repo OWNER/REPO  or  export NLPP_GITHUB_REPO=OWNER/REPO
```

Then patch CIAs on Windows with the drop-bat / `patch_cia`.
