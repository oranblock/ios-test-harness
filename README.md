# iOS Test Harness

Drive **any** iOS simulator build from GitHub Actions, screenshot every step, and
get the whole run pushed to Telegram as it happens plus a timestamped archive at
the end.

Built to be reused across projects and ports: the app arrives by URL, the bundle
id by input, and what to do with it by flow file. Nothing here is specific to one
app.

```
.github/workflows/test-and-report.yml   runner setup, boot, install, package, send
scripts/lib.sh                          helpers: tap, type_text, swipe, send_step…
flows/smoke.sh                          default flow — works on any app, day one
flows/example-login.sh                  worked example to copy per project
```

## Setup, once

Add two repository secrets (**Settings → Secrets and variables → Actions**):

| Secret | Where from |
| :--- | :--- |
| `TELEGRAM_BOT_TOKEN` | @BotFather |
| `TELEGRAM_CHAT_ID` | @userinfobot |

Or from a terminal, so the token never goes through a chat window:

```sh
gh secret set TELEGRAM_BOT_TOKEN --repo <owner>/<repo>
gh secret set TELEGRAM_CHAT_ID  --repo <owner>/<repo>
```

**Both are optional.** With no secrets the run still works and the archive is
still attached to the job — it just skips the Telegram sends.

## Run it

Actions → **iOS Simulator Test & Report** → Run workflow, then give it:

- **app_url** — direct link to a `.zip` containing a **simulator** `.app`
- **bundle_id** — e.g. `com.example.myapp`
- **flow** — `smoke` (default) or your own file under `flows/`
- **device** — default `iPhone 16`; falls back to any available iPhone

### It must be a simulator build

A device build will install and then fail confusingly. Simulator builds need no
signing, which is what makes this cheap:

```sh
xcodebuild -project MyApp.xcodeproj -scheme MyApp \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath dd build
cd dd/Build/Products/Debug-iphonesimulator && zip -qr MyApp-sim.zip MyApp.app
```

Host that zip anywhere the runner can `curl` it — a GitHub release asset, an
artifact URL, S3, a gist.

## Writing a flow

```sh
source "$(dirname "$0")/../scripts/lib.sh"

launch "app_launched"
tap 150 250 "tapped_email"
type_text "user@example.com" "typed_email"
tap 200 400 "tapped_login"
assert_running "login_survived"
```

| Helper | Does |
| :--- | :--- |
| `launch [name]` | cold start, then screenshot |
| `tap X Y name` | tap, settle, screenshot |
| `type_text "…" name` | type into the focused field |
| `swipe X1 Y1 X2 Y2 name` | drag |
| `press HOME\|LOCK name` | hardware button |
| `send_step name [note]` | screenshot + log tail, no interaction |
| `assert_running [name]` | **fails the job** if the process died |
| `terminate` | kill the app |

Every helper numbers its own step, so screenshots sort in execution order.

### Two things that will bite you

**Coordinates are points and device-specific.** A tap that lands on an iPhone 16
misses on an SE. Get real numbers by running `smoke` first and reading positions
off the screenshots in the artifact.

**Tapping is blind.** There is no "wait until this element exists", so a slow
screen means you tap nothing. Raise `TAP_SETTLE` or `LAUNCH_SETTLE`
(`export LAUNCH_SETTLE=8`) rather than sprinkling `sleep`.

## What `assert_running` is for

Without a test runner inside the app, the honest assertion available is *is the
process still alive*. That catches the failures a green build never does: launch
crashes, resume crashes, and layout crashes on rotation. `smoke.sh` exercises all
three and needs no knowledge of the app.

Crash reports from `~/Library/Logs/DiagnosticReports` are collected into the
archive, and the job logs a warning when any are found.

## Cost

`macos-14` runners bill at **10× the minute rate** of Linux on private repos. On
a public repo, standard runners are free. A `smoke` run is a few minutes; a long
flow is not. `timeout-minutes: 45` is a backstop against a hung run quietly
eating the budget.

## Reuse from another repo

The workflow exposes `workflow_call`, so a project can trigger it without copying
anything:

```yaml
jobs:
  ui-test:
    uses: <owner>/ios-test-harness/.github/workflows/test-and-report.yml@main
    with:
      app_url: ${{ needs.build.outputs.sim_zip_url }}
      bundle_id: com.example.myapp
      flow: smoke
    secrets: inherit
```

## Ports and Android

Only iOS today. The same shape works for Android with `ubuntu-latest`, an
emulator action, and `adb shell input tap` / `adb exec-out screencap` in place of
`idb` and `simctl` — and Linux minutes are far cheaper. `scripts/lib.sh` is the
piece worth keeping: the flow files would not change.
