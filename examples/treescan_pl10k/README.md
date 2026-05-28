# TreeScanPL10k → RayCloudTools pipeline

Single-tree and full-plot reconstruction from the TreeScanPL10k dataset using
[RayCloudTools](https://github.com/csiro-robotics/raycloudtools).

---

## Prerequisites

```bash
pip install laspy numpy
docker pull ghcr.io/csiro-robotics/raycloudtools:latest
```

All commands below are run from `examples/treescan_pl10k/` inside the repo.
Create a `work/` subdirectory there for outputs (it is git-ignored).

---

## Data layout

Each `.laz` file in `TreeScanPL10k/batch_XX/` is a single TLS plot (~30 × 30 m,
local coordinates, scanner at origin). Every point carries three extra dimensions:

| LAZ dim | Meaning |
|---|---|
| `treeID` | 0 = background, 1..N = individual trees |
| `treeSP` | Species code (see `species_id_names.csv`) |
| `completelyInside` | 1 = tree fully within plot boundary |

Per-tree ground truth (height, canopy area, species) is in
`individual_tree_summary.csv`.

**Blocker:** all files are LAS point format 0 (no GPS time). `rayimport` requires
GPS time. `prep_laz.py` fixes this by rewriting the file as format 1 with
synthetic monotonically increasing timestamps.

---

## `prep_laz.py` — format conversion and filtering

```
python3 prep_laz.py IN.laz OUT.laz [--tree_id N] [xmin xmax ymin ymax]
```

| Option | Effect |
|---|---|
| *(none)* | Convert entire plot (format 0 → 1) |
| `--tree_id N` | Keep only points where `treeID == N` |
| `xmin xmax ymin ymax` | Spatial crop (can combine with `--tree_id`) |

---

## Single-tree reconstruction

Replace `1` with any `treeID` from the target file.

```bash
# Set DATA to the root of your TreeScanPL10k download
DATA=/path/to/TreeScanPL10k
mkdir -p work

# 1. Extract and convert one tree
python3 prep_laz.py \
  $DATA/batch_01/Rem_Gorlice_2015_0101703.laz \
  work/tree1.laz \
  --tree_id 1

# 2. Import to ray cloud  (scanner at 0,0,0 — local plot coordinates)
docker run --rm --network host -v "$PWD/work":/workspace -w /workspace \
  ghcr.io/csiro-robotics/raycloudtools:latest \
  rayimport tree1.laz 0,0,0

# 3. Extract ground mesh
docker run --rm --network host -v "$PWD/work":/workspace -w /workspace \
  ghcr.io/csiro-robotics/raycloudtools:latest \
  rayextract terrain tree1.ply

# 4. Reconstruct branch cylinders
docker run --rm --network host -v "$PWD/work":/workspace -w /workspace \
  ghcr.io/csiro-robotics/raycloudtools:latest \
  rayextract trees tree1.ply tree1_mesh.ply

# 5. Per-tree stats (volume, DBH, height)
docker run --rm --network host -v "$PWD/work":/workspace -w /workspace \
  ghcr.io/csiro-robotics/raycloudtools:latest \
  treeinfo tree1_trees.txt --crop_length 1

sudo chown -R $USER:$USER work/
```

**Outputs:**

| File | Contents |
|---|---|
| `tree1.ply` | Ray cloud |
| `tree1_mesh.ply` | Ground mesh |
| `tree1_segmented.ply` | Segmented point cloud (coloured by tree) |
| `tree1_trees.txt` | Branch cylinder model |
| `tree1_trees_mesh.ply` | 3-D cylinder mesh — open in MeshLab |
| `tree1_trees_info.txt` | Volume / DBH / height per segment |

The **root segment** row in `_trees_info.txt` holds the whole-tree volume total.
Do not sum all segment volumes — that double-counts.

---

## Full-plot reconstruction

```bash
# 1. Convert entire plot
python3 prep_laz.py \
  $DATA/batch_01/Rem_Gorlice_2015_0101703.laz \
  work/plot.laz

# 2–5. Same Docker commands as above, replacing tree1 with plot
#      rayextract trees will segment all trees automatically.
#      Use --grid_width to match the expected crown diameter (e.g. 5 m).
```

For very large plots use `scripts/rayextract_trees_large.sh` (grid + overlap).

---

## Docker notes

- `--network host` is **required** on this host. `--privileged` does not fix the
  runc sysctl error.
- Outputs are root-owned. Run `sudo chown -R $USER:$USER work/` after each stage.
- The image ships RayCloudTools + TreeTools (`treeinfo`, `treecombine`).

---

## treeID ↔ CSV mapping

`individual_tree_summary.csv` uses 1-based `treeID`; the LAZ `treeID` dimension
starts at 0 (background). Match by point count and height, or trust the species
code (`treeSP` in LAZ = `species_code` in CSV).
