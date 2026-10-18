# ACNextGen Native 4.3

A native C++ enhancement layer for Original Assetto Corsa and Custom Shaders Patch.
The common CSP Physics Worker connects to the native host without adding a
`script.lua` to any car's data folder.

4.3 preserves body force commands in N at physics rate, supported by real paired
body-force probes in local and world coordinates. An experimental lateral body
damping route is enabled only for `wdts_nissan_silvia_s14` on CSP build 3465.
Suspension reaction and rear-LSD application remain disabled pending their own
calibration. Existing yaw damping is unchanged. This does not complete all 51
physical effects. See [CALIBRATION_JP.md](CALIBRATION_JP.md) and
[ENHANCEMENT_CHANNELS.md](ENHANCEMENT_CHANNELS.md).

## What runs where

- **Observer app:** automatic lifecycle, Stop / Resume, permission checks, English dashboard.
- **ACNextGenHost.exe:** read-only AC telemetry, asynchronous model thread, fast effect loop, binary mailboxes.
- **ACNextGenCore.dll:** 51 compiled models and the additional-effect producer. No Lua VM.
- **Common Physics Worker:** physics-rate samples, command validation, bounded force application.

The first connected effect is **additional yaw damping**. The existing
`yaw_moment_budget` risk and authority signals modulate a passive damping moment.
Two opposite forces at car-local Z = +1 m and -1 m have zero net translational
force. They are world-space forces, limited to 20 N per point and 40 Nm of moment.
The Worker rejects positive instantaneous pair power, a stale reference frame,
and stale damping that is too large for the current angular motion.

This is an explicitly additional stability-assist effect. It does not replace
AC's tyre, engine, suspension, or FFB solver. Running 51 models does not mean 51
independent forces are applied.

## Install

Use `ACNextGenNative-v4.2-CM.zip` with Content Manager. Install and enable the
Generic Mod, then enable the `ACNextGen` Lua app. The direct-layout archive is
`ACNextGenNative-v4.2-assettocorsa.zip`.

```text
assettocorsa/
  apps/lua/ACNextGen/
    ACNextGen.lua
    manifest.ini
    modules/{observer,common_bridge,observer_view,performance_metrics}.lua
  extension/plugins/ACNextGenNative/
    bin/{ACNextGenCore.dll,ACNextGenHost.exe}
    common_worker.lua
    enhancement_worker.lua
    config.json
    module_manifest.json
    runtime/
```

No car or track assets are included. No car data files are installed or edited.
The older car-specific adapter remains a research fixture in the source tree.

Start an offline session. The app starts the host and, when CSP permits it, the
common Worker. `Stop` immediately closes the Worker enable gate and pauses native
models. `Resume` changes the control generation, resets model state, and permits
another bounded attempt. Session end invalidates the Worker epoch and shuts down
the managed host.

`config.json` supports `physics_mode: "bounded"` and `physics_mode: "observe"`.
Missing or invalid configuration falls back to observation. Restart the app after
changing the configuration. API errors latch until Resume; the app does not
silently rearm a failed force call.
A fatal model-thread failure remains visible after Resume and requires a host
restart (for example, ending and restarting the session). Resume must not clear
an error belonging to a model thread that has already terminated.

## Permissions and limits

The public CSP API requires physics permission. `physics.allowed()` may depend
on extended track physics and the track's scripting permissions. The dashboard
reports this condition; using a DLL does not bypass it. Offline player car 0 is
the supported target. Online, replay, paused, wrong-car, stale-input, expired
command, and invalid-generation paths inhibit output.

Commands expire after at most **20 ms and 8 physics frames**. Models run at up to
20 Hz in their own thread. The fast native loop targets 200 Hz, while the CSP
Worker validates at the physics rate. Regular `ac.getCar()` supplements remain
render-rate data; their slip/camber angles are converted from degrees to radians.
Physics-rate velocity samples are obtained with the physics APIs.

CSP's force API can invalidate the current lap. This project targets offline
experimentation, not official lap records or multiplayer.

## Build and test

Windows x64, Python 3.10+, Zig 0.14.1, C++17.

```powershell
py -3 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-dev.txt
.\.venv\Scripts\python.exe tools/translate.py
.\build.ps1 -Zig C:\tools\zig\zig.exe
.\Test.ps1 -Python .\.venv\Scripts\python.exe -Zig C:\tools\zig\zig.exe
.\.venv\Scripts\python.exe tools/package_distribution.py
.\.venv\Scripts\python.exe tools/package_source.py
```

The ordinary tests use isolated Windows mappings and CSP API spies. They do not
start the game or apply forces to a real session. Optional configured-car model
comparison uses both `-AcRoot` and `-CarID`. Release installation on this PC has
additional hash gates and reversible backups.
Packaging requires current build/test hashes. Historical performance benchmarks
are optional for contributors; they require a separately saved baseline DLL.

## Evidence

- 51-model original Lua/C++ equivalence: 240 frames and over 1.38 million signals per profile.
- Real DLL producer to production Worker Lua: binary-layout, passive-pair and interlock tests.
- Real EXE/DLL and Windows MMFs to production Worker Lua: ACK, Stop, Resume, identity and exit tests.
- Original CSP API spies verify the exact `physics.addForce` invocation arguments.
- The English dashboard preview is generated from its actual Lua drawing calls with simulated data.

Reports explicitly label whether actual AC/CSP runtime behaviour was tested.
Synthetic API success must not be presented as measured vehicle handling or FPS.
The current evidence is in `reports/`; the original Lua models and registry are
pinned in `reference/` for reproducible regeneration.

See [BRIDGE_PROTOCOL.md](BRIDGE_PROTOCOL.md), [CONTRIBUTING.md](CONTRIBUTING.md),
[PERFORMANCE_CAPTURE.md](PERFORMANCE_CAPTURE.md), [ROADMAP_JP.md](ROADMAP_JP.md),
and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Primary SDK references:
- https://github.com/ac-custom-shaders-patch/acc-lua-sdk/blob/main/ac_background_pw.lua
- https://github.com/ac-custom-shaders-patch/acc-lua-sdk/blob/main/common/ac_extras_connectmmf.lua
- https://github.com/ac-custom-shaders-patch/acc-lua-sdk/blob/main/common/ac_physics_unrestricted.lua
