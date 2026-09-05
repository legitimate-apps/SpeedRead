OBSERVED: `python3 marketing/compose.py` produced all twelve PNGs from the supplied captures. All changes are confined to this new marketing directory. The working tree is intentionally uncommitted; no push, simulator, xcodebuild, app-code change, runtime dependency, or package installation was performed.

OBSERVED: The original CLI screenshot invocation produced an image but timed out during exit. The final implementation uses a standard-library Chrome DevTools Protocol pipe client, an explicit viewport and screenshot clip at scale 1, and an owned browser process with bounded waits and cleanup. The full gallery completed using this implementation. Chrome did not resolve New York by its family name; the final implementation loads the installed macOS regular and italic font files into temporary HTML with CSS font faces. Font files are not redistributed. A canvas metric check detects fallback.

OBSERVED: Every copied raw is byte-identical to its dispatch input. The compositor embeds the complete raw PNG as an image, with proportional browser downscaling, rounded screen masking, and intentional occlusion by the bottom band. No raw was retouched or recoloured. The iPhone image renders at 1029.4375×2236.671875 CSS pixels from 1320×2868; the iPad image renders at 1664.203125×2220.015625 from 2048×2732. Headline-box-to-device clearance is 239.546875 pixels on iPhone and 73.53125 pixels on iPad; the ink marks also clear the device in native-resolution visual inspection. Headline and band text were inspected in native-resolution JPEG crops for all twelve outputs, in addition to gallery overviews and browser geometry checks. The JPEG inspection artifacts are temporary, not upload deliverables.

OBSERVED: Negative controls rejected a missing capture, an iPad capture in the iPhone directory, an iPhone capture in the iPad directory, deliberately oversized text, an upscaled screen and a headline/device collision. The complete `./Scripts/honesty-gates.sh` run passed: actionlint; assertion audit (397 tests, zero assertion-free); lane audit; shared-source audit; executed-test parser control (12 checks); coverage classifier self-test (9 cases). This was a gate run, not execution of the app's 397 tests.

OBSERVED: Both supplied night captures contain the system “Enjoying SpeedRead?” rating dialog. Both Browse captures show “No Library Servers”; the iPad version is a sheet over the library. These states remain visible in output frames 05 and 06. No clean replacement captures were supplied, and capture/editing work was excluded from this task. All twelve frames rendered, but the night frames need clean raw replacements before upload. Replace the two `raw/*/03-reader-night.png` files with clean same-size captures and run `python3 marketing/compose.py --only 05`. A populated Browse capture would also demonstrate the promised benefit more clearly.

ASSUMED (editorial judgment): The frame 03 band “Books in a day, without moving your eyes” overpromises a reading outcome and literal eye immobility. Suggested alternative: “Set your pace. Let the words come to you.” The approved wording remains unchanged in the generated gallery. App behavior, reading outcomes and App Store upload acceptance were not independently exercised in this compositor task.

OBSERVED: Independent Pillow dimension verification printed:

```text
marketing/out/ipad/01.png: 2048x2732
marketing/out/ipad/02.png: 2048x2732
marketing/out/ipad/03.png: 2048x2732
marketing/out/ipad/04.png: 2048x2732
marketing/out/ipad/05.png: 2048x2732
marketing/out/ipad/06.png: 2048x2732
marketing/out/iphone/01.png: 1290x2796
marketing/out/iphone/02.png: 1290x2796
marketing/out/iphone/03.png: 1290x2796
marketing/out/iphone/04.png: 1290x2796
marketing/out/iphone/05.png: 1290x2796
marketing/out/iphone/06.png: 1290x2796
```

OBSERVED: Files added, with one-line reasons (no pre-existing files changed):

- `marketing/README.md` — One-paragraph rerun instructions, prerequisites and output locations.
- `marketing/REPORT.md` — Implementation handoff, observed limitations, verification and file inventory.
- `marketing/checks/ipad-01.json` — Per-frame browser geometry, font check and raw/output SHA-256 evidence.
- `marketing/checks/ipad-02.json` — Per-frame browser geometry, font check and raw/output SHA-256 evidence.
- `marketing/checks/ipad-03.json` — Per-frame browser geometry, font check and raw/output SHA-256 evidence.
- `marketing/checks/ipad-04.json` — Per-frame browser geometry, font check and raw/output SHA-256 evidence.
- `marketing/checks/ipad-05.json` — Per-frame browser geometry, font check and raw/output SHA-256 evidence.
- `marketing/checks/ipad-06.json` — Per-frame browser geometry, font check and raw/output SHA-256 evidence.
- `marketing/checks/iphone-01.json` — Per-frame browser geometry, font check and raw/output SHA-256 evidence.
- `marketing/checks/iphone-02.json` — Per-frame browser geometry, font check and raw/output SHA-256 evidence.
- `marketing/checks/iphone-03.json` — Per-frame browser geometry, font check and raw/output SHA-256 evidence.
- `marketing/checks/iphone-04.json` — Per-frame browser geometry, font check and raw/output SHA-256 evidence.
- `marketing/checks/iphone-05.json` — Per-frame browser geometry, font check and raw/output SHA-256 evidence.
- `marketing/checks/iphone-06.json` — Per-frame browser geometry, font check and raw/output SHA-256 evidence.
- `marketing/compose.py` — Rerunnable compositor with native Chrome rendering and fail-loud validation.
- `marketing/out/ipad/01.png` — Finished Chrome-rendered gallery PNG in requested frame order and device well.
- `marketing/out/ipad/02.png` — Finished Chrome-rendered gallery PNG in requested frame order and device well.
- `marketing/out/ipad/03.png` — Finished Chrome-rendered gallery PNG in requested frame order and device well.
- `marketing/out/ipad/04.png` — Finished Chrome-rendered gallery PNG in requested frame order and device well.
- `marketing/out/ipad/05.png` — Finished Chrome-rendered gallery PNG in requested frame order and device well.
- `marketing/out/ipad/06.png` — Finished Chrome-rendered gallery PNG in requested frame order and device well.
- `marketing/out/iphone/01.png` — Finished Chrome-rendered gallery PNG in requested frame order and device well.
- `marketing/out/iphone/02.png` — Finished Chrome-rendered gallery PNG in requested frame order and device well.
- `marketing/out/iphone/03.png` — Finished Chrome-rendered gallery PNG in requested frame order and device well.
- `marketing/out/iphone/04.png` — Finished Chrome-rendered gallery PNG in requested frame order and device well.
- `marketing/out/iphone/05.png` — Finished Chrome-rendered gallery PNG in requested frame order and device well.
- `marketing/out/iphone/06.png` — Finished Chrome-rendered gallery PNG in requested frame order and device well.
- `marketing/raw/ipad/01-library.png` — Unedited supplied native capture, retained for self-contained reruns.
- `marketing/raw/ipad/02-reader-parchment.png` — Unedited supplied native capture, retained for self-contained reruns.
- `marketing/raw/ipad/03-reader-night.png` — Unedited supplied native capture, retained for self-contained reruns.
- `marketing/raw/ipad/04-rsvp-paused.png` — Unedited supplied native capture, retained for self-contained reruns.
- `marketing/raw/ipad/05-rsvp-playing.png` — Unedited supplied native capture, retained for self-contained reruns.
- `marketing/raw/ipad/06-browse.png` — Unedited supplied native capture, retained for self-contained reruns.
- `marketing/raw/iphone/01-library.png` — Unedited supplied native capture, retained for self-contained reruns.
- `marketing/raw/iphone/02-reader-parchment.png` — Unedited supplied native capture, retained for self-contained reruns.
- `marketing/raw/iphone/03-reader-night.png` — Unedited supplied native capture, retained for self-contained reruns.
- `marketing/raw/iphone/04-rsvp-paused.png` — Unedited supplied native capture, retained for self-contained reruns.
- `marketing/raw/iphone/05-rsvp-playing.png` — Unedited supplied native capture, retained for self-contained reruns.
- `marketing/raw/iphone/06-browse.png` — Unedited supplied native capture, retained for self-contained reruns.

OBSERVED: Supporting JSON evidence and this handoff are the only deliverables beyond the requested tool, captures, gallery and rerun note. No unrelated subsystem changes were made.
