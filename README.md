# nlpp-gold

Publishes **`bake_img.bin`** + **`romfs_overlay.zip`** for
[NewLovePlusPlusEngPatcher](https://github.com/czyrustuazon/NewLovePlusPlusEngPatcher)
consumers. You edit EngPatcher; this repo only runs the Ubuntu bake and hosts Releases.

```text
  push / merge → EngPatcher main
        → Request gold Release (dispatches here)
        → self-hosted Ubuntu bake
        → Release tag "gold" (assets replaced)
        → fetch_release_bake.py --tag gold
```

Other EngPatcher branches do nothing. Full PNG pack can take many hours.
CIA / drop-bat patching stays on **Windows**.

---

## Getting started (one-time)

**Requirements:** Ubuntu **x86_64** (not Pi / ARM), Tailscale or SSH to the box, a vanilla New Love Plus+ RomFS extract on your PC.

### 1. Clone this repo on the server

```bash
git clone https://github.com/OWNER/THIS_REPO.git ~/git-actions/nlpp-gold
cd ~/git-actions/nlpp-gold
```

### 2. Create directories + packages

```bash
sudo bash scripts/prepare-runner-dirs.sh /opt/nlpp
sudo apt-get update
sudo apt-get install -y python3 python3-venv python3-pip zip git gh
```

`gh` (GitHub CLI) publishes the Release. If `apt` can't find it, add GitHub's apt repo
first: <https://github.com/cli/cli/blob/trunk/docs/install_linux.md>.

That creates `/opt/nlpp/vanilla` (`romfs/` + `exefs/`), `/opt/nlpp/actions-runner`, `/opt/nlpp/cache/img_pack`.  
It does **not** install the GitHub Actions runner yet.

### 3. Copy vanilla files from your PC

You need the **Japanese/vanilla** RomFS extract — **not** EngPatcher’s `release/` folder
(`bake_img.bin` / `romfs_overlay` are gold *outputs*).

Typical local source:

```text
...\New Love Plus Plus\extracted\romfs\
  img.bin
  SystemData\TextResource\textresource_jpn.trb
  SystemData\TextResource\textresource_resident_jpn.trb
...\New Love Plus Plus\extracted\exefs\
  code.bin          (use code.bin.bak if present — that is the untouched copy)
```

Server destinations:

| File | On server |
|------|-----------|
| `img.bin` | `/opt/nlpp/vanilla/romfs/img.bin` |
| `textresource_jpn.trb` | `/opt/nlpp/vanilla/romfs/SystemData/TextResource/` |
| `textresource_resident_jpn.trb` | `/opt/nlpp/vanilla/romfs/SystemData/TextResource/` |
| `exefs\code.bin` | `/opt/nlpp/vanilla/exefs/code.bin` |

`code.bin` is required — the bake patches it into `release/name_input_code.bin`.

**From PowerShell on your Windows PC** (Tailscale connected; replace host/user/path):

```powershell
$server = "zepse@mainserver"   # Tailscale MagicDNS name or 100.x.x.x
$src = "C:\Users\YOU\Documents\New Love Plus Decompilation\New Love Plus Plus\extracted\romfs"
$exefs = "$src\..\exefs"

# /opt/nlpp was created as root — fix ownership first (-t = sudo can ask for password)
ssh -t $server "sudo mkdir -p /opt/nlpp/vanilla/exefs && sudo chown -R `$USER:`$USER /opt/nlpp/vanilla"

scp "$src\img.bin" "${server}:/opt/nlpp/vanilla/romfs/img.bin"
scp "$src\SystemData\TextResource\textresource_jpn.trb" `
  "${server}:/opt/nlpp/vanilla/romfs/SystemData/TextResource/"
scp "$src\SystemData\TextResource\textresource_resident_jpn.trb" `
  "${server}:/opt/nlpp/vanilla/romfs/SystemData/TextResource/"
scp "$exefs\code.bin" "${server}:/opt/nlpp/vanilla/exefs/code.bin"
```

If `scp` says **Permission denied**, ownership wasn’t fixed — re-run the `ssh -t ... chown` line.  
If `sudo: A terminal is required`, you omitted `-t`.

On the server, confirm:

```bash
ls -lh /opt/nlpp/vanilla/romfs/img.bin
ls -lh /opt/nlpp/vanilla/romfs/SystemData/TextResource/
ls -lh /opt/nlpp/vanilla/exefs/code.bin
```

### 4. Install the GitHub Actions runner

1. GitHub → **this repo** → **Settings → Actions → Runners → New self-hosted runner**
2. Choose **Linux** / **x64**
3. On the server:

```bash
cd /opt/nlpp/actions-runner
# paste GitHub’s curl + tar commands here
./config.sh --url https://github.com/OWNER/THIS_REPO --token PASTE_TOKEN_FROM_GITHUB
sudo ./svc.sh install
sudo ./svc.sh start
```

`svc.sh` only exists **after** you extract the runner tarball. It is not in this git clone.  
Confirm the runner shows **Idle** under Settings → Actions → Runners.

### 5. Point the runner at vanilla

Put these in the runner environment so jobs see them. Easiest: copy
[`.env.example`](.env.example) → `/opt/nlpp/actions-runner/.env`:

```bash
NLPP_VANILLA_IMG=/opt/nlpp/vanilla/romfs/img.bin
NLPP_VANILLA_CODE=/opt/nlpp/vanilla/exefs/code.bin
NLPP_VANILLA_TRB=/opt/nlpp/vanilla/romfs/SystemData/TextResource/textresource_jpn.trb
NLPP_VANILLA_RESIDENT_TRB=/opt/nlpp/vanilla/romfs/SystemData/TextResource/textresource_resident_jpn.trb
NLPP_PACK_CACHE=/opt/nlpp/cache/img_pack
```

Restart the service:

```bash
cd /opt/nlpp/actions-runner
sudo ./svc.sh stop
sudo ./svc.sh start
```

### 6. Wire EngPatcher → this repo

On **EngPatcher**:

1. Secret `NLPP_GOLD_DISPATCH_TOKEN` = a PAT that can
   `POST /repos/OWNER/THIS_REPO/dispatches`
   (fine-grained: only this repo, **Contents: Read and write**)
2. Variable `NLPP_GOLD_REPO=OWNER/THIS_REPO`. EngPatcher defaults to
   `OWNER/nlpp-gold-maker`, so set this if your repo has any other name.
3. Ensure `.github/workflows/request-gold-release.yml` is on EngPatcher `main`

If EngPatcher is **private**, add secret `ENGPATCHER_CHECKOUT_TOKEN` on **this** repo
(contents:read).

Optional vars on this repo: `NLPP_PACK_WORKERS`, `NLPP_ENGPATCHER_REPO`
(default `OWNER/NewLovePlusPlusEngPatcher`), `NLPP_ENGPATCHER_REF`.
Manual runs are limited to the repo owner.

Optional secrets for the companion-site progress bar: `NLPP_PROGRESS_ENDPOINT`,
`NLPP_PROGRESS_TOKEN`. If unset, that step is skipped.

### 7. Smoke test

- Push/merge to EngPatcher **`main`**, or  
- This repo → **Actions → Release gold bake → Run workflow**

Watch the self-hosted job. First full pack can take many hours.

---

## Consume (collaborators)

From an EngPatcher clone (any OS):

```bash
python tools/fetch_release_bake.py --repo OWNER/THIS_REPO --tag gold
# or: export NLPP_GITHUB_REPO=OWNER/THIS_REPO
```

Then patch CIAs on Windows with the drop-bat / `patch_cia`.
