# Device test runbook — ARKit volumetric capture (Tier A/B)

The turnkey steps to test the volumetric scanner on a real iPhone and bank a
weighed eval set. The app is wired for an **auth-free** debug entry, so no
Google sign-in and no tokens are needed. See `README.md` for the per-dish
capture protocol; this file is just the run mechanics.

## Prerequisites
- Mac with Xcode, this repo, `backend/.venv` (has numpy/opencv).
- The iPhone + a USB cable. **Base iPhone 17 = Tier B** (ARKit metric pose, no
  LiDAR → carve leans on segmentation). **iPhone 17 Pro = Tier A** (LiDAR dense
  depth, the better test).
- A kitchen scale.
- An https tunnel tool (`cloudflared` or `ngrok`). iOS blocks cleartext HTTP to a
  LAN IP and this project has no ATS exception, so the app must reach the backend
  over https. (No tunnel tool? Ask and we'll add an `NSAllowsLocalNetworking`
  exception instead.)

## 1. Start the backend, banking captures into the eval dataset
```bash
cd backend
VOLUMETRIC_CAPTURE_DIR=eval/realworld/dataset \
  ./.venv/bin/python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```
The dev venv has numpy/opencv, so the `/v1/scan/volumetric` route mounts. `.env`
supplies the Claude + USDA keys. Each capture is saved under
`eval/realworld/dataset/<dish_id>/` BEFORE the pipeline runs, so a provider hiccup
never loses raw data.

## 2. Expose it over https
```bash
cloudflared tunnel --url http://localhost:8000     # or: ngrok http 8000
```
Copy the printed `https://…` URL.

## 3. Point the app at it and open the capture tool (Xcode scheme args)
Open `ios/Riva.xcodeproj` → Product → Scheme → Edit Scheme → Run → Arguments →
"Arguments Passed On Launch", add:
```
-riva.volumetric
-riva.scanService https://<your-tunnel-url>
```
No auth args needed — `-riva.volumetric` opens the capture screen auth-free.

## 4. Run on the device
Plug in the iPhone, pick it as the run destination, press Run. First run on a new
device: on the phone, Settings → General → VPN & Device Management → trust the
developer cert. (Signing is automatic, team already set.) The app launches
straight into the capture screen.

## 5. Capture each dish (~1 min)
1. Weigh the plated food → note grams.
2. In the app: type the dish **name** + **grams** (+ a **hint** for hidden oil/
   butter/cream).
3. Tap-and-hold and sweep a smooth **3–5 s arc** from ~45° down to top-down,
   keeping the dish centered and filling the frame.
4. Submit. Aim for **20–30 dishes**: light vs heavy, flat vs piled, single-item
   vs mixed bowls, and a few dense rice mounds (where 2D scanners fail).

## 6. Verify the haul (on the Mac)
```bash
cd backend
ls eval/realworld/dataset/
./.venv/bin/python eval/realworld/ingest.py     # validates each dish + frame count
```
Each dish dir should have `frames/`, `arkit_poses.json`, `manifest.json`,
`truth.json` (with your grams).

## 7. Score it
Come back and the harness gets a `volumetric` predictor added, then:
```bash
./.venv/bin/python eval/realworld/run_realworld_eval.py --predictor volumetric
```
GO / no-go vs the v1 baseline: **GO** if R² ≥ 0.6 AND grams MAPE ≤ 20% (v1 is ~23%).

## Honest caveats for this test
- **Base iPhone 17 (Tier B):** the carve uses ARKit pose + **classical GrabCut**
  masks, which over-include the plate (seen on the burger clip). Expect rough
  accuracy; the value is proving the loop on-device and banking real data. **SAM 2**
  (gated, needs a Replicate token) would materially improve masks.
- **iPhone 17 Pro (Tier A):** LiDAR dense depth is far less segmentation-dependent
  and is the stronger test — lights up automatically via the runtime tier check.
