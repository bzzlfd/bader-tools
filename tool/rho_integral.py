#!/usr/bin/env python3
"""rho_integral.py -- integrate a PWmat OUT.RHO density over the cell.

reads the density grid from an OUT.RHO file (little-endian fortran
sequential unformatted, same format as mod_pwmat_io.f90 reads:

   record 1        : int32   n1, n2, n3, nnodes (may hold one extra int32)
   record 2        : float64 lattice vectors, angstrom, ordered as
                     a1x, a1y, a1z, a2x, a2y, a2z, a3x, a3y, a3z
   records 3-...   : nnodes records of float64 grid data; each holds at
                     least nr = n1*n2*n3/nnodes values (may be padded),
                     linear index i1*n2*n3 + i2*n3 + i3, n3 fastest

and prints
   integral = sum(rho) * V_cell[bohr^3] / (n1*n2*n3)   [electrons]

which is the same value convert_rho2cube.x reports as "integral of the
mixed density over the cell".

usage:
   rho_integral.py OUT.RHO [OUT.RHO2 ...]

only python stdlib + numpy.
"""

import argparse
import struct
import sys

import numpy as np

# 1 bohr radius in angstrom, same constant as mod_utils.f90
BOHR_ANG = 0.529177239


def read_record(f, path):
    """read one fortran sequential unformatted record, return its payload."""
    head = f.read(4)
    if not head:
        die(f"unexpected end of {path} (record header)")
    (nbytes,) = struct.unpack("<i", head)
    data = f.read(nbytes)
    if len(data) != nbytes:
        die(f"unexpected end of {path} (record payload)")
    (tail,) = struct.unpack("<i", f.read(4))
    if tail != nbytes:
        die(f"record marker mismatch in {path}: {nbytes} != {tail}")
    return data


def read_rho(path):
    """return (rho[n1*n2*n3] float64, AL[3,3] angstrom, n, nnodes).

    AL[:, i] is lattice vector a_i, matching the Fortran readers.
    """
    with open(path, "rb") as f:
        rec = read_record(f, path)
        n1, n2, n3, nnodes = struct.unpack_from("<4i", rec)
        rec = read_record(f, path)
        AL = np.frombuffer(rec, dtype="<f8", count=9).reshape(3, 3, order="F")
        if min(n1, n2, n3, nnodes) <= 0:
            die(f"unphysical grid in {path}: {n1} x {n2} x {n3}, {nnodes} nodes")
        npt = n1 * n2 * n3
        if npt % nnodes:
            die(f"n1*n2*n3 not divisible by nnodes in {path}")
        nr = npt // nnodes
        rho = np.empty(npt)
        for i in range(nnodes):
            rec = read_record(f, path)
            if len(rec) < 8 * nr:
                die(f"data record {i + 1} too short in {path}")
            rho[i * nr : (i + 1) * nr] = np.frombuffer(rec, dtype="<f8", count=nr)
    return rho, AL, (n1, n2, n3), nnodes


def die(msg):
    sys.exit(f"ERROR: {msg}")


def main():
    ap = argparse.ArgumentParser(
        description="integrate a PWmat OUT.RHO density over the cell (electrons)"
    )
    ap.add_argument("rho", nargs="+", help="OUT.RHO file(s)")
    args = ap.parse_args()

    for path in args.rho:
        rho, AL, n, nnodes = read_rho(path)
        cellvol_bohr = abs(np.linalg.det(AL)) / BOHR_ANG**3
        integral = rho.sum() * cellvol_bohr / rho.size
        print(f"== {path} ==")
        print(f"  grid = {n[0]} x {n[1]} x {n[2]}  ({rho.size} points), "
              f"nnodes = {nnodes}")
        print(f"  cell volume = {cellvol_bohr:.6f} bohr^3")
        print(f"  integral of the density over the cell = {integral:.8f} e")
        print(f"  density min = {rho.min():.8f}   max = {rho.max():.8f}"
              f"   [e/bohr^3]")


if __name__ == "__main__":
    main()
