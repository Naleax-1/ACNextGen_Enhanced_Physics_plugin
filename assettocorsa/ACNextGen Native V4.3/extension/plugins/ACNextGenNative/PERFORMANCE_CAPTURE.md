# Render performance evidence

The Observer records render timing from `ui.deltaTime()` into a uniquely named
`extension/plugins/ACNextGenNative/runtime/performance-*.jsonl` file. It records
live offline sessions only. Replay, pause, and missing native readiness are
excluded. It never changes controls or enables an effect for measurement.

Each one-second window contains frame count, duration, mean FPS, frame-time
p50/p95/p99/max, and 1% low FPS derived from the slowest 1% of that window.
It also records car/track identity, requested mode, SDK FPS, model cost, model
age, API/applied counters, and module timings from the latest native snapshot.
Metadata and JSON serialization happen once per window. A file has at most
3,600 successful windows. A logging failure stays separate from physics control.

## Compare Stop / Resume

Use the same car, track, weather, camera, rendering settings, and traffic.
Warm up first. For an initial stationary comparison, record Stop for 60 seconds,
Resume for 60 seconds, then Stop for 60 seconds again. Repeat separately while
driving a comparable route. Mode transitions discard a partial timing window.
Ignore the first five seconds of each phase when summarizing.

```powershell
python tools/summarize_render_metrics.py <performance-file.jsonl> --output comparison.json
```

The reader preserves each contiguous phase, including the second Stop. It
reports weighted mean FPS, the median of per-window p99 frame times, and the
worst observed frame. It does not pretend that per-window percentiles combine
into a whole-run percentile. A single screenshot FPS value is not an A/B result.
The baseline includes ordinary AC rendering and the Observer; Stop pauses the
models/effect, but leaves the common Worker sensor capture running.

The compiled-model benchmark is separate:

```powershell
python tests/benchmark_runtime.py --baseline <saved-previous-Core.dll>
```

V4.0 to V4.1 was measured on identical synthetic inputs in an alternating order.
Model mean time changed from 33.10 ms to 28.72 ms (13.2% reduction). This result
does not establish the real-game FPS improvement. The argument/result container
keeps up to four values inline and uses a heap-backed list for longer calls.
All 51 models retained the tested Lua numerical behavior.
