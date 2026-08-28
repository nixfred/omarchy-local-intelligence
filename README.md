# Local Intelligence

An Omarchy Shell bar widget for Ollama. Its status ring is green while the
local AI runtime is idle, pulses neon blue during inference, and turns red
when Ollama cannot be reached.

Activity is detected from a short Ollama runner CPU sample and, when available,
NVIDIA or AMD GPU utilization. Hover for the active model and measured load.
Click the ring for a live utilization meter and model control panel; select any
installed Ollama model to load and keep warm, or unload it from memory. Right
click refreshes immediately.

## Install

```bash
omarchy plugin add https://github.com/nixfred/omarchy-local-intelligence.git --enable
```

For local development, link or copy this directory to:

```text
~/.config/omarchy/plugins/io.github.nixfred.local-intelligence
```

Then enable it with
`omarchy plugin enable io.github.nixfred.local-intelligence right`. The
`refreshIntervalMs` and `activeThreshold` options are configurable from the bar
widget settings or directly in `~/.config/omarchy/shell.json`.

## Use

- Left click the ring to open model controls.
- Right click to refresh immediately.
- Choose an installed model to load and keep warm, or unload it from memory.

IPC is also available:

```bash
omarchy-shell io.github.nixfred.local-intelligence status
omarchy-shell io.github.nixfred.local-intelligence refresh
omarchy-shell io.github.nixfred.local-intelligence toggle
```

## Requirements

- Omarchy Quattro with third-party shell plugin support
- Python 3
- Ollama listening on `OLLAMA_HOST` or `http://127.0.0.1:11434`
- Optional: `nvidia-smi` or `rocm-smi` for GPU-aware activity

The plugin talks only to the configured Ollama HTTP endpoint and reads local
process counters from `/proc`. It does not download models or other software.

## Remove

```bash
omarchy plugin remove io.github.nixfred.local-intelligence --yes
```

## License

MIT
