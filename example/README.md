# NaCl 示例数据

本目录包含四组 PWmat 数据和四组自算 VASP PBE 数据。计算方法、电荷转移结果及分析见 [NaCl 实验笔记](../note/NaCl-experiment.md)。

## PWmat

| 目录 | 赝势与计算设置 | 网格 | 电荷密度文件 |
| --- | --- | --- | --- |
| `NaCl.FHILDA/` | FHI LDA；Na 1、Cl 7 个价电子 | 36³ | `OUT.RHO` |
| `NaCl.SG15PBE/` | SG15 PBE；Na 9、Cl 7 个价电子 | 36³ | `OUT.RHO` |
| `NaCl.SG15PBE.SPIN2/` | SG15 PBE；Na 9、Cl 7；共线自旋极化 | 36³ | `OUT.RHO`、`OUT.RHO_2` |
| `NaCl.zval1.SG15PBE/` | PBE；Na 1、Cl 7 个价电子 | 36³ | `OUT.RHO` |

每组同时保留 `atom.config`、`etot.input` 和 UPF 赝势。`OUT.RHO` 是 Fortran 二进制文件；自旋极化数据的两个文件分别保存两个自旋通道的电荷密度。

`etot.input` 记录原始计算设置，其中 `IN.PSP*` 使用原有上级目录相对路径。

## VASP

| 目录 | Na 价电子数 | 电荷密度网格 | 说明 |
| --- | ---: | --- | --- |
| `NaCl.VASP_Na9Cl7_48/` | 9 | 48³ | 默认稀疏网格 |
| `NaCl.VASP_Na9Cl7_160/` | 9 | 160³ | 密网格，仅保留计算输入 |
| `NaCl.VASP_Na1Cl7_36/` | 1 | 36³ | 默认稀疏网格 |
| `NaCl.VASP_Na1Cl7_120/` | 1 | 120³ | 密网格，仅保留计算输入 |

四组均为 VASP 5.4.4、PBE、`ISPIN=2`，使用同一八原子晶胞（4 个 Na、4 个 Cl）和 4×4×4 Monkhorst–Pack k 点网格。Na9、Na1 的平面波截断能分别为 645.6 eV、262.5 eV。

两组默认稀疏网格数据包含：

- `CHGCAR`：原始价电子电荷密度；
- `AECCAR0`、`AECCAR2`：芯密度和重构的全电子价密度；
- `INCAR`、`KPOINTS`、`POSCAR`：计算设置、k 点和原始结构。

两组密网格目录仅保留 `INCAR`、`KPOINTS`、`POSCAR`；体积较大的 `CHGCAR`、`AECCAR0`、`AECCAR2` 不纳入仓库。相应分析结果仍记录在[实验笔记](../note/NaCl-experiment.md)及其数据文件中。

VASP 目录后缀表示电荷密度网格的单边格点数。所用 PBE PAW 数据集分别为 Na9 的 `Na_sv`、Na1 的 `Na`，以及两组共用的 `Cl`；Cl 均有 7 个价电子。目录中未附 `POTCAR`，具体赝势标签和文件哈希见[数据记录](../note/data/NaCl-weight-results.json)。
