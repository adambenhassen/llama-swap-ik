# amd64 only — build with: docker build --platform linux/amd64 ...
# Stage 1: build ik_llama.cpp's llama-server
FROM debian:bookworm-slim AS ik-build

ARG IK_COMMIT=bbc7de475178dd0535c16ad85f204a2529806c9d
# Mainline llama.cpp tag whose committed pre-built web UI we bundle for the ik
# server (newer tags build the UI from source at compile time instead)
ARG WEBUI_REF=b6900
# Requires AVX2 at build time (ik's iqk sources don't compile without it).
# Override when the build host's native features differ from the target's,
# e.g. building under Rosetta: "-DGGML_NATIVE=OFF -DGGML_AVX2=ON -DGGML_FMA=ON -DGGML_F16C=ON"
ARG CPU_FLAGS="-DGGML_NATIVE=ON"

RUN apt-get update && apt-get install -y --no-install-recommends \
        git gcc g++ cmake make ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone https://github.com/ikawrakow/ik_llama.cpp.git . \
    && git checkout "$IK_COMMIT"

# -include cstdint: iqk_common.h uses uint64_t without including <cstdint>,
# which newer GCC rejects
RUN cmake -B build $CPU_FLAGS -DLLAMA_CURL=OFF -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CXX_FLAGS="-include cstdint" \
    && cmake --build build --target llama-server -j4

# Collect the binary and all shared libs it needs into one dir
RUN mkdir /out \
    && cp build/bin/llama-server /out/ \
    && find build -name '*.so*' -exec cp -a {} /out/ \;

# Mainline web UI (single-file SPA), served by the ik server via --path
ADD https://raw.githubusercontent.com/ggml-org/llama.cpp/${WEBUI_REF}/tools/server/public/index.html.gz /webui/index.html.gz
RUN gunzip /webui/index.html.gz

# Stage 2: overlay onto stock llama-swap CPU image
FROM ghcr.io/mostlygeek/llama-swap:cpu

# No global LD_LIBRARY_PATH: the mainline /app/llama-server must not pick up
# ik's conflicting libllama.so. Set it per-command in llama-swap's config.
COPY --from=ik-build /out/ /app/ik/
COPY --from=ik-build /webui/index.html /app/ik/webui/index.html
