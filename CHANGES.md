# Changelog

## 1.0.1 — 2026-08-27

### Fixed
- **OMTELEPROMPT-UNBOUNDED-VAD-RESTART** (`Panel.qml:193`): `vadProcess.onExited` previously restarted `bin/vad.py` immediately via `Qt.callLater` with no retry ceiling or backoff. When all optional audio backends are absent (`pyaudio`, `sounddevice`, `parecord`, `arecord`) or persistently fail to initialize, the helper exits immediately (exit code 1) and the long-lived `omarchy-shell` entered an unbounded process-spawn loop. Fixed by:
  - Adding bounded retry state: `vadFailureCount`, `vadMaxRetries=5`, `vadBaseRetryDelayMs=1000`, `vadPermanentFailure`, `vadManualStop` (`Panel.qml:27`)
  - Replacing immediate restart with exponential backoff via `vadRetryTimer` — delays `1s, 2s, 4s, 8s, 16s` capped at `30s` (`Panel.qml:180`)
  - Adding `vadStableTimer` (`5s`) to reset `vadFailureCount` after a stable run, so transient failures don’t accumulate (`Panel.qml:201`)
  - Gating `vadTimer` on `!vadPermanentFailure && !vadRetryTimer.running && !vadProcess.running` and max-retries check, interval raised from `100ms` to `1000ms` (`Panel.qml:156`)
  - Updating `vadProcess.onExited` to increment failure count, set `Voice Error` (`#ff8800`) and `console.warn` after 5 failures, and give up until voice is toggled (`Panel.qml:228`)
  - Updating voice toggle (`Panel.qml:378`) to set `vadManualStop`, reset counters, stop timers, and start VAD explicitly with `vadStableTimer.restart()`
  - Guarding `voiceLevel` write against undefined target (`Panel.qml:229`)
- Bumped `manifest.json:5` version `1.0.0` → `1.0.1`

### Notes
- Validated at `e7831d3d52669d0127cb550c91fd1c9547c350d4` with `omarchy plugin validate` (exit `0`)
- No network, privilege escalation, or config-overwrite changes; voice remains opt-in via `voiceEnabled` setting
- Reviewed SHA for previous submission: `8bc35b7f7316b06da2c1e24d01a0a8b27f1a235a`

## 1.0.0 — 2026-08-26

- Initial release: `BarWidget.qml`, `Panel.qml`, `bin/vad.py`, `manifest.json:1`, `README.md`, `LICENSE`
- Features: word tracking, auto-scroll, voice activation (pause-on-speak), notes panel, adjustable `fontSize`/`scrollSpeed`/`vadThreshold`
- Marketplace assets: `assets/omteleprompt.png`, `README.md` install/configure/remove instructions
