#!/usr/bin/env python3
"""Prepare CSIRO RayCloudTools-compatible LAZ from the TreeScanPL10k files.

Fixes the blocker that rayimport rejects point-format-0 files ("No timestamps
found on laz file, these are required") by writing point format 1 with a
synthetic gps_time field. Optionally spatial-crops to a tile or filters to a
single pre-labeled tree using the treeID extra dimension.

Usage:
  prep_laz.py IN.laz OUT.laz [--tree_id N] [xmin xmax ymin ymax]

  --tree_id N    Keep only points where treeID == N (TreeScanPL10k extra dim).
  xmin xmax ymin ymax  Spatial crop (applied after --tree_id if both are given).
"""
import sys, argparse, numpy as np, laspy

parser = argparse.ArgumentParser()
parser.add_argument("input")
parser.add_argument("output")
parser.add_argument("--tree_id", type=int, default=None,
                    help="Keep only points with this treeID value")
parser.add_argument("crop", nargs="*", type=float,
                    metavar="xmin/xmax/ymin/ymax",
                    help="Optional spatial crop: xmin xmax ymin ymax")
args = parser.parse_args()

las = laspy.read(args.input)
x, y = np.asarray(las.x), np.asarray(las.y)
n0 = len(x)
keep = np.ones(n0, bool)

if args.tree_id is not None:
    tree_ids = np.asarray(las.treeID)
    keep &= tree_ids == args.tree_id
    print(f"  treeID={args.tree_id}: {keep.sum():,} points before spatial crop")

if len(args.crop) == 4:
    xmin, xmax, ymin, ymax = args.crop
    keep &= (x >= xmin) & (x <= xmax) & (y >= ymin) & (y <= ymax)
elif len(args.crop) != 0:
    parser.error("crop requires exactly 4 values: xmin xmax ymin ymax")

# Build a fresh point-format-1 file (format 1 carries gps_time).
hdr = laspy.LasHeader(version="1.2", point_format=1)
hdr.scales, hdr.offsets = las.header.scales, las.header.offsets
out = laspy.LasData(hdr)
out.x = x[keep]; out.y = y[keep]; out.z = np.asarray(las.z)[keep]
out.intensity = np.asarray(las.intensity)[keep].astype(np.uint16)
# Synthetic monotonically increasing time (no real timestamps in source data).
out.gps_time = np.arange(int(keep.sum()), dtype=np.float64)
out.write(args.output)
print(f"{args.input}: kept {keep.sum():,} / {n0:,} points -> {args.output}")
