#!/usr/bin/env python3
"""Regenerate the three NaCl density figures from the adjacent published CSVs.

Run from any directory with Python 3, NumPy and Matplotlib installed.
Only the three assets/NaCl-path-PBE-*.png files are replaced.
"""

from pathlib import Path
import json
import os
import tempfile

import numpy as np


DATA = Path(__file__).resolve().parent
ASSETS = DATA.parent.parent / 'assets'
BEFORE = '#4d4d4d'
AFTER = '#0072b2'
NA_CORE = '#009e73'
CL_CORE = '#e69f00'


def density_axes(ax, distance):
    ax.set(xlim=(0, distance), ylim=(0, .4),
           ylabel=r'Charge density (e / bohr$^3$)')
    ax.set_yticks(np.arange(0, .401, .1))
    ax.grid(alpha=.18, linewidth=.7)
    ax.set_axisbelow(True)
    ax.text(.012, .025, 'Na', transform=ax.transAxes, va='bottom', color='#444')
    ax.text(.988, .025, 'Cl', transform=ax.transAxes,
            va='bottom', ha='right', color='#444')


def radius_band(ax, distance, radii):
    ax.set(xlim=(0, distance), ylim=(0, 1))
    ax.set_axis_off()
    ax.axhline(.12, color='#b6bec8', lw=.8)
    for element, color in [('Na', NA_CORE), ('Cl', CL_CORE)]:
        by_radius = {}
        for row in radii[element]:
            by_radius.setdefault(row['rc_bohr'], []).append(row)
        for radius, rows in by_radius.items():
            target = radius if element == 'Na' else distance - radius
            linestyle = '-' if any(row['core_occupancy'] > 0 for row in rows) else '--'
            ax.vlines(target, .015, .25, colors=color, lw=1.4,
                      linestyles=linestyle)
        for i, row in enumerate(radii[element]):
            radius = row['rc_bohr']
            target = radius if element == 'Na' else distance - radius
            label = (f"{element} {row['configuration_label']}: "
                     f"$r_c$ = {radius:g} bohr")
            linestyle = '-' if row['core_occupancy'] > 0 else '--'
            ax.annotate(label, xy=(target, .25), xycoords='data',
                        xytext=(.015 if element == 'Na' else .985, .91-i*.32),
                        textcoords='axes fraction', va='center',
                        ha='left' if element == 'Na' else 'right',
                        color=color, fontsize=10.5,
                        arrowprops=dict(arrowstyle='-', color=color, lw=.95,
                                        linestyle=linestyle,
                                        shrinkA=3, shrinkB=0))


def single(plt, zval, sample, checks):
    x = sample['x_bohr']
    distance = x[-1]
    fig = plt.figure(figsize=(11.5, 6.8))
    gs = fig.add_gridspec(2, 1, height_ratios=[1.5, 4.8], hspace=.035,
                         left=.10, right=.97, bottom=.105, top=.88)
    radius_band(fig.add_subplot(gs[0]), distance, checks['construction_cutoffs'])
    ax = fig.add_subplot(gs[1])
    ax.scatter(x, sample['rho_valence_e_per_bohr3'], s=30,
               color=BEFORE, zorder=4, label='Valence charge density')
    ax.scatter(x, sample['rho_reference_e_per_bohr3'], s=78,
               facecolors='none', edgecolors=AFTER, linewidths=1.5, zorder=5,
               label='Reference: valence + Na and Cl core densities')
    for element, tag, color in [('Na', f'Na{zval}', NA_CORE),
                                ('Cl', 'Cl', CL_CORE)]:
        table = np.genfromtxt(DATA / f'NaCl-core-{tag}.csv', delimiter=',', names=True)
        core_x = table['r_bohr'] if element == 'Na' else distance - table['r_bohr']
        keep = (core_x >= 0) & (core_x <= distance)
        ax.plot(core_x[keep], table['rho_core_e_per_bohr3'][keep],
                color=color, lw=1.8, zorder=2,
                label=f'{element} atomic core density')
    density_axes(ax, distance)
    ax.set_xlabel(r'Distance from Na along Na $\rightarrow$ Cl (bohr)')
    ax.legend(loc='upper center', fontsize=10, framealpha=.95)
    fig.suptitle(f'PWmat PBE Na{zval}: charge density along Na–Cl',
                 fontsize=16, y=.97)
    fig.savefig(ASSETS / f'NaCl-path-PBE-Na{zval}.png')
    plt.close(fig)


def comparison(plt, samples):
    fig, axes = plt.subplots(2, 1, figsize=(11.5, 8), sharex=True,
                             gridspec_kw={'hspace': .22})
    fig.subplots_adjust(left=.10, right=.97, bottom=.095, top=.86)
    panels = [
        ('rho_valence_e_per_bohr3', BEFORE, 'Before core correction: valence density'),
        ('rho_reference_e_per_bohr3', AFTER, 'After core correction: reference density'),
    ]
    for ax, (column, color, title) in zip(axes, panels):
        for zval in (9, 1):
            sample = samples[zval]
            if zval == 9:
                ax.scatter(sample['x_bohr'], sample[column], marker='o',
                           facecolors='none', edgecolors=color, s=85,
                           linewidths=1.5, label='Na9', zorder=3)
            else:
                ax.scatter(sample['x_bohr'], sample[column], marker='x',
                           color=color, s=46, linewidths=1.6, label='Na1', zorder=4)
        density_axes(ax, samples[9]['x_bohr'][-1])
        ax.set_title(title, fontsize=12, loc='left', color=color, pad=10)
        ax.legend(loc='upper center', fontsize=10.5, framealpha=.95, ncol=2)
    axes[-1].set_xlabel(r'Distance from Na along Na $\rightarrow$ Cl (bohr)')
    fig.suptitle('Charge density before and after core correction\nPWmat PBE: Na9 and Na1',
                 fontsize=16, y=.97, linespacing=1.5)
    fig.savefig(ASSETS / 'NaCl-path-PBE-comparison.png')
    plt.close(fig)


def main():
    # The temporary font cache is a runtime artifact, separate from figure data.
    with tempfile.TemporaryDirectory(prefix='nacl-plot-mpl-') as cache:
        os.environ['MPLCONFIGDIR'] = cache
        import matplotlib
        matplotlib.use('Agg')
        import matplotlib.pyplot as plt

        plt.rcParams.update({'font.family': 'DejaVu Sans', 'font.size': 11,
                             'axes.spines.top': False, 'axes.spines.right': False,
                             'savefig.dpi': 200})
        samples = {zval: np.genfromtxt(DATA / f'NaCl-path-Na{zval}.csv',
                                      delimiter=',', names=True) for zval in (9, 1)}
        checks = json.loads((DATA / 'NaCl-weight-results.json').read_text())
        for zval, info in zip((9, 1), checks['path_figures']['checks']['materials']):
            single(plt, zval, samples[zval], info)
        comparison(plt, samples)


if __name__ == '__main__':
    main()
