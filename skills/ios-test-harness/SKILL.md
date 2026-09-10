---
name: ios-test-harness
description: Build and RUN an iOS app in GitHub Actions — compile for the simulator, launch it, screenshot/record every screen, and report to Telegram, a GitHub issue, or a secret gist. Use when asked to test an iOS app in CI, get screenshots or video of an iOS app, diagnose which screens crash, compile a private iOS/KMP project on free macOS runners, or when no Mac is available. Repo: oranblock/ios-test-harness.
---

## What this is

`github.com/oranblock/ios-test-harness` — a public repo with two workflows that
together build any iOS project and drive the resulting app on a simulator.

```
Build iOS Simulator App       private source -> .app zip artifact -> issue + Telegram
iOS Simulator Test & Report   that artifact  -> launch, screenshot, video -> Telegram
```

Deliberately app-agnostic: source repo by input, bundle id by input, behaviour by
flow file. A new project means a new flow, not edited workflows.

**Public repo, private source, on purpose.** macOS runners are free on public
repos and bill at 10× on private ones. The source is checked out with a token and
never published; compiler output goes to Telegram and a secret gist, and only the
error COUNT and FILE NAMES reach the public issue.

## Running it

```sh
# 1. compile (produces an artifact)
gh workflow run "Build iOS Simulator App" --repo oranblock/ios-test-harness \
  -f source_repo=owner/repo -f ref=branch \
  -f prebuild=iosApp/fetch-filament.sh \
  -f runner=macos-15 -f xcode=16

# 2. run it (takes the artifact from that run id)
gh workflow run "iOS Simulator Test & Report" --repo oranblock/ios-test-harness \
  -f artifact_run_id=<build run id> -f bundle_id=com.example.app \
  -f flow=diagnose -f runner=macos-15 -f xcode=16
```

Secrets: `SOURCE_REPO_TOKEN` (read a private repo), `TELEGRAM_BOT_TOKEN` +
`TELEGRAM_CHAT_ID` (optional), `GIST_TOKEN` (optional, classic PAT with `gist`).

## Flows

| flow | does |
| :--- | :--- |
| `smoke` | launch, background, resume, rotate — knows nothing about the app |
| `diagnose` | launch into EVERY screen, prove each survives, screenshot each |
| `video` | burst-capture frames and send them (see "Video" below) |

Helpers in `scripts/lib.sh`: `launch`, `launch_screen`, `visit`, `tap`,
`type_text`, `swipe`, `press`, `send_step`, `record_clip`, `assert_running`,
`report_screens`.

---

# Hard-won facts

Everything below cost a CI round to learn. Read before debugging.

## Drive screens by launch env, never by blind taps

If the app reads an environment variable at launch (Skirmish:
`ProcessInfo.processInfo.environment["SKIRMISH_SCREEN"]` in `SkirmishApp.swift`),
use it. `simctl` passes env through the **`SIMCTL_CHILD_`** prefix:

```sh
env SIMCTL_CHILD_SKIRMISH_SCREEN=forge xcrun simctl launch "$UDID" "$BUNDLE_ID"
```

**A tap that lands on nothing produces a screenshot of the PREVIOUS screen and a
passing run.** That is the worst failure mode available: a green sweep of
identical pictures. Coordinates are also device-specific and layout-fragile.

An unrecognised env value usually falls through to a default screen — which is
how you skip a first-run onboarding/language gate without completing it.

**One screen per launch.** A crash then names itself instead of ending the sweep.

## Metal, simulators, and what genuinely cannot be tested

- Runners are `macos-14-arm64` / `macos-15` — **Apple Silicon with
  paravirtualised Metal. Metal works.** SceneKit renders and records fine. The
  "Metal is broken on CI" advice is about pre-2024 Intel runners and is obsolete.
- **Filament cannot run on ANY iOS simulator.** Verified on Xcode 15.4/iOS 17 and
  Xcode 16.4/iOS 26:

```
FEngine::loop -> abort_with_reason
  MTLSimDriver_encountered_XPC_error
  MTLSimDriver -[MTLSimArgumentEncoder setBuffers:offsets:withRange:]
```

  The simulator proxies Metal over XPC and argument buffers break that proxy.
  Screens using Filament need real hardware, permanently. Screens using SceneKit,
  UIKit or SwiftUI are fully testable.

## The toolchain is part of the result

Always pin and log the Xcode version. Same commit, different verdicts:

| screen | Xcode 15.4 | Xcode 16.4 |
| :--- | :--- | :--- |
| fleet | ❌ crash | ✅ ok |
| saloon, battlebench | ❌ | ❌ (Filament) |

A screen that "crashes" may only be crashing on an old runtime. Log
`xcrun simctl list runtimes` so a failure is attributable rather than guessed at.

## Swift concurrency: fix the property, not the file

Swift 5.10 rejects main-actor patterns Swift 6 accepts. Two classes dominate:

**`call to main actor-isolated ... in a synchronous nonisolated context`** — put
`@MainActor` on the **View struct**, never on individual members. Annotating a
member moves the boundary to its caller and the error walks outward one file per
CI round. Swift 6 makes `View` conformance imply this anyway.

**`reference to captured var 'self' in concurrently-executing code`** — an outer
`{ [weak self] in ... }` wrapping `Task { @MainActor in ... }`. The inner Task
needs **its own** `[weak self]`.

**Error counts lie.** The compiler stops reporting a file once it fails to
type-check, so the count moving matters far less than the SET moving:
`9 → 4 → 6 → 1 → 12 → 1 → 0`. When it names a file, ask how many other files have
that shape, and sweep for it.

## Runner gotchas that cost a round each

- **`bash -e`.** GitHub runs every step with it. `cmd > log 2>&1; rc=$?` exits
  before `rc` is captured, and `[ -f x ] && y` as the last line of a loop body
  kills the step. Put `set +e` first in any step that inspects its own failure.
- **Homebrew refuses third-party taps**: "Refusing to load formula
  facebook/fb/idb-companion from untrusted tap". Make idb OPTIONAL — launch,
  screenshots and liveness are pure `simctl`, and those catch the real crashes.
- **idb needs `--udid`** on every call. `idb connect` alone is not enough:
  "No udid provided and there no companions". Probe with
  `idb list-targets --udid` — `command -v idb` says nothing about a companion.
- **`gh gist create` has NO `--secret` flag.** Gists are secret by default;
  `--public` opts out. Passing `--secret` prints usage and exits 1, which looks
  like an auth failure and is not.
- **Artifacts need auth.** `curl` on the UI link returns HTML. Use
  `gh run download <run_id>` — which also keeps the binary private.
- **Concurrency groups must include the inputs.** A group keyed only on workflow
  name means dispatching an Xcode 15 run silently CANCELS the Xcode 16 run of the
  same commit — and comparing toolchains is the entire point.
- **`recordVideo` must be stopped with SIGINT.** Anything harder leaves an
  unfinalised, unplayable file.
- **Fetch large binary deps.** Vendored prebuilts (Filament) are usually
  gitignored; run the project's fetch script via the `prebuild` input, or the
  build dies with "no XCFramework found", which looks like a code error.

## Video: capture frames, not video

`simctl io recordVideo` **does not work in CI.** It finalises its mp4 only on
SIGINT, and across three attempts it never stopped on one:

| attempt | why it failed |
| :--- | :--- |
| `xcrun simctl io ... &` then `kill -INT $!` | `$!` is xcrun's pid; it forks simctl and exits |
| `pkill -INT -f "simctl io .* recordVideo"` | found the process, signal had no effect |
| `$(xcrun --find simctl) io ... &` then `kill -INT $!` | `$!` was the recorder; still ignored it |

Killing it harder produces an **8 MB file with media data and no `moov` atom** —
plausible size, reports success, plays nowhere. One was sent to Telegram as if
fine.

Use a **burst of screenshots** instead. Every frame is complete when written, so
the worst case is fewer frames rather than a corrupt file that claims to be good.
`record_clip` captures `CLIP_FPS` (default 5) frames per second, stitches with
ffmpeg if present, and otherwise sends the stills.

**There is no ffmpeg on the macOS runner images**, so in practice it sends
frames. That is fine: several stills a fraction of a second apart answer "is it
moving", which is the only question a clip is for.

**Proving animation:** `md5sum` every frame. 15 of 15 unique means the scene is
genuinely animating; identical hashes mean a stalled render or a static image.
That is evidence; "it looks animated" is not.

**If you produce an mp4 anywhere, check it:** `grep -qa moov file.mp4`. A size
proves a file exists, not that it opens.

## idb is effectively unavailable in CI

Homebrew refuses the tap on both macos-14 and macos-15 ("Refusing to load formula
facebook/fb/idb-companion from untrusted tap"), and `HOMEBREW_ALLOW_UNTRUSTED_TAPS`
did not get past it. **So taps, typing, swipes and rotation do not run in CI
today.** Everything that catches a crash — launch, screenshots, liveness — is
pure `simctl` and works.

Design flows so this degrades rather than blocks: prefer launch-env navigation,
treat taps as a bonus, and never let a missing idb fail a run.

## The Android side lives in its own skill

`android-test-harness` (repo `oranblock/Android-test-harness`) is the sibling of
this one: same shape, Linux runners at 1x instead of macOS at 10x, and taps that
actually work. Its constraints are different enough to be their own document —
the emulator action runs each LINE of `script:` as a separate shell, flows must
not use `set -e`, and `applicationIdSuffix` changes the package id. Load that
skill for Android, not this one.

## The shell lies, three ways

Each of these cost a full CI round in one session. They share a shape: the code
looks like it says one thing and the shell does another.

| written | actually |
| :--- | :--- |
| `cmd > log 2>&1; rc=$?` | `bash -e` exits at `cmd`; `rc` never runs |
| `xcrun tool ... & ; kill $!` | `$!` is the WRAPPER, not the tool |
| `[ -f x ] && y` ending a loop body | returns 1 when absent, `set -e` kills the step |
| `kill -KILL "$pid"` | returns 1 if already dead, `set -e` kills the step |

Rule: any step that inspects its own failure starts with `set +e`, and any helper
producing evidence rather than an assertion ends with `return 0`.

## Telegram

A bot token from @BotFather is static — **no OTP, no session, no login**. That is
the *client* API (MTProto), which is a different thing. One gotcha: a bot cannot
start a conversation, so message it once with `/start` or every send fails 403.
`TELEGRAM_CHAT_ID` is numeric, negative for groups.

## Keeping private source out of a public repo

Redact by construction, and make failures readable anyway:

- build steps redirect to a FILE, never stdout (compiler errors quote source)
- the public issue carries status, counts and FILE NAMES only
- full logs go to Telegram and a secret gist
- report gist/Telegram failures explicitly — a silent redaction step is worse
  than none, because nobody can tell it is broken

## Read the screenshots

They answer questions no log does. From one sweep: the app never left its
first-run language picker; its active row was clipped under the status bar (a
missing top safe-area inset); and background particles moved between frames,
proving animation. Download with `gh run download`, unzip, and actually look.

---

# Known blockers

Not bugs to fix — limits to design around.

| blocker | status |
| :--- | :--- |
| **Filament screens cannot run on any iOS simulator** | Permanent. Argument buffers break the simulator's XPC Metal proxy; verified on Xcode 15.4/iOS 17 and 16.4/iOS 26. These screens need real hardware. |
| **idb unavailable** (Homebrew refuses the tap) | No taps/typing/swipes/rotation in CI. Use launch-env navigation. |
| **No ffmpeg on runner images** | Clips ship as frames, not mp4. |
| **`simctl io recordVideo` unusable** | Never finalises on SIGINT in CI. Use the frame burst. |
| **Artifacts are public on a public repo** | Keep app binaries as artifacts (auth-gated download), never release assets. |

When a screen fails, check the toolchain before the code: the same commit gave
different verdicts on Xcode 15.4 and 16.4, and one "crash" was purely the older
runtime.
