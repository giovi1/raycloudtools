# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

RayCloudTools is a C++ library (`raylib`) plus a set of command-line tools (`raycloudtools/ray*`) for
processing **ray clouds**: point clouds where each point also stores the sensor origin at observation time.
The sensor direction is encoded in the PLY `normal` field (nx,ny,nz = vector from end point back to the
sensor), so a ray cloud represents free space as well as surfaces — enabling operations (transient removal,
combination, smoothing) that are impossible on plain point clouds.

## Build

```bash
mkdir build && cd build
cmake ..            # defaults to Release build type
make -j$(nproc)
```

Binaries land in `build/bin/`. To run tools from anywhere, add `build/bin` to `PATH` and
`/usr/local/lib` (and any optional-dep install dirs) to `LD_LIBRARY_PATH`.

**Required deps:** Eigen3, [libnabo](https://github.com/ethz-asl/libnabo) (build from a tagged release,
e.g. 1.1.2), OpenMP, Threads.

**Optional feature flags** (off by default; toggle with `-DWITH_X=ON` or `ccmake ..`):
- `WITH_LAS` — .las/.laz import/export (needs LASzip 3.x C API; LAS 1.0–1.4 incl. COPC)
- `WITH_QHULL` — enables the `raywrap` tool (convex/concave hulls)
- `WITH_TIFF` — render to GeoTIFF (needs libgeotiff + TIFF + PROJ)
- `WITH_TBB` — Intel TBB multi-threading
- `WITH_NORMAL_FIELD` (default ON) — store rays in PLY nx,ny,nz vs. rayx,rayy,rayz fields
- `DOUBLE_RAYS` — store ray ends as doubles for large-coordinate clouds

## Running the prebuilt Docker image

The published image (`ghcr.io/csiro-robotics/raycloudtools:latest`, built from `docker/Dockerfile`)
ships every `ray*` tool plus [TreeTools](https://github.com/csiro-robotics/treetools) (`treeinfo`,
`treecombine`, `treecolour`) and is built `WITH_LAS WITH_QHULL WITH_TIFF DOUBLE_RAYS`. Typical run,
mounting a host data dir as the workspace:

```bash
docker run --rm -v "$PWD":/workspace -w /workspace \
  ghcr.io/csiro-robotics/raycloudtools:latest <tool> <args>
```

- The container runs as **root**, so outputs are root-owned. Add `--user $(id -u):$(id -g)` to avoid
  `chown`-ing results afterwards.

See `examples/treescan_pl10k/` for a worked example with the TreeScanPL10k dataset
(includes `prep_laz.py` to handle the format-0 / no-GPS-time blocker).

### Individual-tree reconstruction / biomass pipeline

The canonical sequence (also see `scripts/rayextract_trees_large.sh` for the grid+overlap version on
large clouds):
`rayimport` (laz→ray cloud) → `raydecimate` (optional, e.g. `1 cm`) → `rayextract terrain` (ground mesh)
→ `rayextract trees cloud.ply mesh.ply` (writes `_trees.txt`, `_segmented.ply`, `_trees_mesh.ply`) →
`treeinfo _trees.txt --crop_length 1` (per-tree volume/DBH/height; volume × wood density = biomass).
In `_trees.txt`/`_info.txt` the **root segment's `volume` field already holds the whole-tree total**
(spec: "volume of segment / total tree volume") — sum per-segment volumes only over non-root segments,
or just read the root value, otherwise you double-count.

### LAS/LAZ import gotchas

- `readLas` (`raylib/raylaz.cpp`) **rejects any file without GPS time** ("No timestamps found on laz
  file, these are required"). LAS **point format 0/2 has no GPS time** → must be rewritten to format
  1/3 with a (synthetic) `gps_time` before `rayimport` will accept it.
- `rayimport cloud.laz 0,0,0` puts the sensor at the origin — correct only for **plot-/sensor-centred
  local coordinates**. For projected/UTM clouds use `--remove_start_pos` or a constant `ray 0,0,-10`
  model, else all rays become near-parallel pointing at a far origin.
- Default `--max_intensity 100` maps LAS intensity to the 0–255 alpha (alpha>0 = "bounded" ray);
  LAS extra dims (e.g. `treeID`) are **not** imported.

## Tests

Tests are gated behind a CMake flag and are **integration tests**: `tests/raytest/raytests.cpp` shells out
to the built `ray*` executables and validates the resulting `.ply` files, so the binaries must be on the
run path.

```bash
cmake .. -DRAYCLOUD_BUILD_TESTS=ON && make -j$(nproc)
cd bin && ./raytest                       # run directly from build/bin (cwd matters)
# or, from build/:
ctest . --output-on-failure
```

Run a single test with the GoogleTest filter, e.g. `./raytest --gtest_filter=Basic.RayDecimate`.
Full output is always written to `build/Testing/Temporary/LastTest.log`. CI (`.github/workflows/test.yml`)
builds + tests on Ubuntu 22.04 and 24.04.

## Architecture

- **`raylib/`** — the core shared library. All real logic lives here. Key pieces:
  - `raycloud.{h,cpp}` — the `Cloud` class, the central data structure (parallel arrays of `starts`,
    `ends`, `times`, `colours`; a ray is "bounded" iff alpha > 0). Most algorithms are methods on `Cloud`.
  - `rayply.cpp` / `raylaz.cpp` — PLY and LAS/LAZ I/O; `raycloudwriter.cpp` for chunked/streamed writing.
  - `rayparse.{h,cpp}` — shared command-line argument parsing used by every tool.
  - `*gen.cpp` (`rayroomgen`, `rayforestgen`, `raytreegen`, `rayterraingen`, `raybuildinggen`) — synthetic
    cloud generators behind `raycreate`.
  - `extraction/` — the heavier feature-extraction algorithms (`raytrees`, `raytrunks`, `rayforest`,
    `rayterrain`, `rayleaves`, `raysegment`) used by `rayextract`.
- **`raycloudtools/ray*/`** — one directory per CLI tool, each just a thin `.cpp` wrapping `raylib` (see
  any `*.cpp`'s `usage()` for the full, authoritative argument spec). Add a new tool by creating a
  subdir with a `ras_add_executable(... LIBS raylib)` CMakeLists and registering it in
  `raycloudtools/CMakeLists.txt`.
- **`cmake/`** — the `Ras*` CMake helper modules (`RasAddExecutable`, `RasAddLibrary`, `RasProjectSetup`,
  `RasClangTidy`, etc.) and `Find*.cmake` scripts for the optional deps. Tools/libs are defined via these
  `ras_*` macros, not raw `add_executable`/`add_library`.
- **`3rd-party/simple_fft`** — vendored FFT used by alignment (`rayalign`).

`raylibconfig.in.h` is configured at build time into `raylibconfig.h`, exposing the `WITH_*` /
`DOUBLE_RAYS` flags as compile-time `1/0` macros.

## Conventions

- C++ style is enforced by `.clang-format` and `.clang-tidy` (the `ras_clang_tidy_target` machinery wires
  these in). Match the surrounding code; sections of generated usage text are wrapped in
  `// clang-format off` / `on`.
- The `.devcontainer/` provides a ready VS Code dev environment; `docker/Dockerfile` builds a full image
  (`docker build -f docker/Dockerfile -t raycloudtools:local .`).
