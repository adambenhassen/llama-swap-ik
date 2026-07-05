# llama-swap-ik

Custom [llama-swap](https://github.com/mostlygeek/llama-swap) Docker image that
bundles an [ik_llama.cpp](https://github.com/ikawrakow/ik_llama.cpp) server
alongside the stock mainline llama.cpp one, for CPU inference. **amd64 only.**

The base image ships mainline `llama-server` at `/app/llama-server`. This image
adds ik_llama.cpp's server (plus its shared libs) at `/app/ik/`, so each model
in llama-swap's `config.yaml` can choose either server per its `cmd`.
ik_llama.cpp measured ~10-15% faster CPU prefill on a gemma-4 MoE.

It also bundles mainline's web UI (single-file SPA) at `/app/ik/webui/`, so
the ik server can serve the modern UI instead of its dated built-in one.

## Build

```bash
docker build --platform linux/amd64 -t llama-swap-ik .
```

Takes ~15-20 minutes (compiles ik_llama.cpp from source).

The default `GGML_NATIVE=ON` tunes the binary to the build host's CPU —
**build on the machine that will run it**, and rebuild if you move to
different hardware. ik's iqk sources require AVX2 to compile; on a build host
that doesn't expose it natively (e.g. an ARM Mac emulating amd64 via
Rosetta), override the CPU flags:

```bash
docker build --platform linux/amd64 \
  --build-arg CPU_FLAGS="-DGGML_NATIVE=OFF -DGGML_AVX2=ON -DGGML_FMA=ON -DGGML_F16C=ON" \
  -t llama-swap-ik .
```

Watchtower-style auto-updaters can't update a locally built image; you must
rebuild manually to pick up llama-swap base image updates.

## Using the ik server in config.yaml

The real `config.yaml` lives with your deployment, not in this repo. Example:

```yaml
models:
  # mainline llama.cpp server (stock)
  "some-model":
    cmd: >
      /app/llama-server
      -m /models/some-model.gguf
      --host 127.0.0.1 --port ${PORT}

  # ik_llama.cpp server, serving mainline's web UI
  "some-model-ik":
    cmd: >
      env LD_LIBRARY_PATH=/app/ik /app/ik/llama-server
      -m /models/some-model.gguf
      --path /app/ik/webui
      --host 127.0.0.1 --port ${PORT}
```

`LD_LIBRARY_PATH=/app/ik` is set per-command (not globally in the image) so
the mainline server doesn't load ik's conflicting `libllama.so`.

`--path /app/ik/webui` makes the ik server serve mainline's web UI. Omit it to
get ik's built-in UI. The UI talks to `/v1/chat/completions` and `/props`,
which ik supports; newer UI features tied to newer mainline endpoints may not
work.

### Flag-dialect gotchas (ik vs mainline)

- ik's `-fa` takes `on|off` and **defaults to on**. A bare `-fa` is a parse
  error on ik (mainline uses `-fa 1`).
- ik puts model thinking into `message.reasoning_content` unless you pass
  `--reasoning off`.

## Bumping ik_llama.cpp

Pin a newer **tested** commit and rebuild:

```bash
docker build --platform linux/amd64 --build-arg IK_COMMIT=<commit-sha> -t llama-swap-ik .
```

The default commit is set in the `Dockerfile` (`ARG IK_COMMIT=...`); update it
there once a newer commit is validated. `WEBUI_REF` pins the mainline tag the
bundled web UI comes from (must be a tag that still commits the pre-built
`tools/server/public/index.html.gz`; tags after ~b6900 build the UI from
source instead).
