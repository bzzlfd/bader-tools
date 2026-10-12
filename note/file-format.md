# 电荷密度文件格式与适配

本文介绍 PWmat、Gaussian 和 VASP 的电荷密度文件格式，并说明为 `bader` 程序适配 PWmat 数据时的格式选择与注意事项。

## PWmat

### `OUT.RHO`

PWmat 的 `OUT.RHO` 是 Fortran 顺序非格式化二进制文件
（`access='sequential', form='unformatted'`）。文件由以下记录组成：

| 记录 | 数据类型 | 内容 |
| --- | --- | --- |
| 1 | 4 个 `int32` | 网格尺寸 `n1, n2, n3` 和数据分块数 `nnodes`；某些文件还包含第 5 个整数 `NSTATE`（状态数），本项目仅处理第一个状态 |
| 2 | 9 个 `float64` | 晶格矩阵 `AL(3,3)`，单位为 Å；`AL(:,i)` 是第 `i` 个晶格矢量 |
| 3 至 `nnodes+2` | `nr` 个 `float64` | 电荷密度数据，单位为 e/bohr³；`nr = n1*n2*n3/nnodes`，记录末尾可能有填充 |

每次顺序非格式化 `read` 操作读取一条记录，自动处理记录标记，并跳过该记录中未读取的尾部数据。
核心读取代码如下（整数使用 `int32`，晶格和电荷密度使用 `float64`）：

```fortran
open(newunit=u, file='OUT.RHO', status='old', &
     access='sequential', form='unformatted', convert='little_endian')
read(u) n1, n2, n3, nnodes
read(u) AL                    ! Å

nr = n1*n2*n3 / nnodes
allocate(rho1d(n1*n2*n3))
do inode = 1, nnodes
   off = (inode - 1)*nr
   read(u) rho1d(off + 1 : off + nr)
end do
close(u)
```

这里约定，三维数组 `rho3d` 与一维数组 `rho1d` 的映射按第三个下标变化最快的顺序排列。
网格下标从 1 开始时，`rho3d(i1,i2,i3)` 对应 `rho1d((i1-1)*n2*n3 + (i2-1)*n3 + i3)`：

```fortran
allocate(rho3d(n1,n2,n3))
do i1 = 1, n1
   do i2 = 1, n2
      do i3 = 1, n3
         k = (i1-1)*n2*n3 + (i2-1)*n3 + i3
         rho3d(i1,i2,i3) = rho1d(k)
      end do
   end do
end do
```

Fortran 数组在内存中按第一个下标变化最快的顺序存储，因此不能直接用 `reshape(rho1d, [n1,n2,n3])` 得到上述映射关系。

### `atom.config`

PWmat 的 `OUT.RHO` 包含晶格和电荷密度网格，但不包含原子坐标，因此需要从 `atom.config` 文件中额外读取原子信息。
相比之下，Gaussian 的 `.cube` 文件和 VASP 的 `CHGCAR` 文件都包含晶体结构信息。

`atom.config` 是文本文件，使用 `LATTICE` 和 `POSITION` 作为区块关键字（card）。
这两个区块的顺序可以交换，区块之间可以有空行：

| 位置或区块 | 内容 |
| --- | --- |
| 首个非空行 | 原子数 `natom` |
| `LATTICE` 区块 | 关键字后为三个晶格矢量，每行依次为 `x`、`y`、`z` 分量，单位为 Å |
| `POSITION` 区块 | 关键字后为 `natom` 行 `Z fx fy fz mx my mz`：原子序数、三个分数坐标分量和三个移动标志；本例只读取前四项 |

```fortran
open(newunit=u, file='atom.config', status='old')
rewind(u)
read(u, *) natom
allocate(Z(natom), xfrac(natom,3), xcart(natom,3))

rewind(u)
call find_atom_card('LATTICE')
do j = 1, 3
   read(u, *) AL(:,j)               ! Å
end do

rewind(u)
call find_atom_card('POSITION')
do i = 1, natom
   read(u, *) Z(i), xfrac(i,1:3)
end do

do i = 1, natom
   xcart(i,1:3) = matmul(AL, xfrac(i,1:3))
end do
```

`atom.config` 与 `OUT.RHO` 中的晶格应一致。

## Gaussian 的 `.cube` 文件

Gaussian 的 `.cube` 文件是文本文件，包含网格、原子信息和电荷密度数据：

| 行 | 内容 |
| --- | --- |
| 1–2 | 两行注释 |
| 3 | `natom ox oy oz nval`：原子数、网格原点、每个网格点的数值个数；本项目使用的原点为 `(0,0,0)`，且 `nval = 1` |
| 4–6 | `ni vix viy viz`：第 `i` 个方向的网格点数和步进矢量 `vi = ai/ni`；步进矢量表示相邻网格点之间的位移，网格不重复包含周期边界处的点；根据 `bader` 程序的多极矩（multipole）计算代码推断，其单位为 bohr |
| 后续 `natom` 行 | `Z charge x y z`：原子序数、核电荷字段、笛卡尔坐标；`charge` 不参与 `bader` 1.05 的分析和结果输出，本项目将其设为 `0` |
| 剩余行 | 网格上的电荷密度值，按第三个下标变化最快的顺序排列 |

```fortran
open(newunit=u, file='out.cube', status='old')
read(u, *)
read(u, *)
read(u, *) natom, origin(1:3)
read(u, *) n1, voxel(1:3)
AL(:,1) = n1 * voxel(1:3) ! bohr
read(u, *) n2, voxel(1:3)
AL(:,2) = n2 * voxel(1:3) ! bohr
read(u, *) n3, voxel(1:3)
AL(:,3) = n3 * voxel(1:3) ! bohr
allocate(Z(natom), xcart(natom,3), xfrac(natom,3))
do i = 1, natom
   read(u, *) Z(i), charge, xcart(i,1:3)
end do
allocate(rho1d(n1*n2*n3))
do i = 1, n1
   do j = 1, n2
      off = (i-1)*n2*n3 + (j-1)*n3
      read(u, '(6E13.5)') rho1d(off + 1 : off + n3)
   end do
end do
close(u)
```

## VASP 的 `CHGCAR` 文件

VASP 的 `CHGCAR` 文件是文本文件，包含晶体结构、网格数据和 PAW 单中心占据数据。

| 区块 | 内容 |
| --- | --- |
| 晶体结构 | `POSCAR` 格式的晶格、元素及原子坐标 |
| 网格尺寸 | 三个整数 `n1 n2 n3`，对应 `NGXF NGYF NGZF` |
| 网格数据 | 共 `n1*n2*n3` 个实数；存储值为无量纲的 `data3d = rho3d * Vcell` |
| PAW 占据数据 | PAW 单中心占据数据（augmentation occupancies） |

`POSCAR` 格式在 VASP 5 中发生过一次变化，`bader` 程序可以自动识别 VASP 4 和 VASP 5 的格式。
网格尺寸、网格数据和 PAW 占据数据共同构成一个数据区块，后面还可能存在相同格式的磁性数据区块。`bader` 程序只读取第一个区块中的网格数据。

下面是读取 `CHGCAR` 的简化伪代码，未覆盖所有格式情况：

```fortran
open(newunit=u, file='CHGCAR', status='old')
read(u, *)
read(u, *) scale
do j = 1, 3
   read(u, *) AL(:,j)
end do
AL = scale * AL                                 ! Å

read(u, '(a)') line
if (is_species_line(line)) read(u, '(a)') line  ! 伪代码：跳过 VASP 5 的元素符号行
counts = parse_integer_list(line)               ! 伪代码：VASP 4 直接读取原子数行
natom = sum(counts)
read(u, *)                                      ! 假设坐标类型为 Direct，跳过该行
allocate(xfrac(natom,3), xcart(natom,3))
do i = 1, natom
   read(u, *) xfrac(i,1:3)
   xcart(i,1:3) = matmul(AL, xfrac(i,1:3))
end do

read(u, *) n1, n2, n3
allocate(data3d(n1,n2,n3))
read(u, *) (((data3d(i1,i2,i3), i1=1,n1), i2=1,n2), i3=1,n3)
close(u)
```

VASP 与 PWmat 的文件格式主要有以下区别：

1. 晶体结构：VASP 的 `POSCAR` 格式要求将同类原子分组并按顺序写入，PWmat 的 `atom.config` 则允许自由排列原子顺序。
2. 网格数据：`CHGCAR` 按第一个下标变化最快的顺序存储，PWmat 的 `OUT.RHO` 则按第三个下标变化最快的顺序存储。
3. 自旋极化电荷密度：**共线自旋极化**计算中，VASP 的 `CHGCAR` 将总电荷密度存储在第一个数据区块中；PWmat 则将自旋向上和自旋向下的电荷密度分别存储在 `OUT.RHO` 和 `OUT.RHO_2` 中。

## 格式选择

Gaussian 的 `.cube` 格式的以下特点与 PWmat 的文件格式契合：

1. 允许自由排列原子顺序
2. 网格数据按第三个下标变化最快的顺序存储

选择 `.cube` 格式便于实现数据转换，也便于用户按原始原子顺序核对分析结果，因此本项目将其作为适配程序的输出格式。

## 注意事项

### 共线自旋极化计算（`SPIN=2`）

`bader` 程序需要使用总电荷密度进行 Bader 分析。因此，对于 PWmat 的 `SPIN=2` 计算，适配时需要将两个自旋通道的电荷密度逐点相加，再写入 `.cube` 文件。

### `.cube` 文件的长度单位

本项目的 `.cube` 文件使用原子单位制描述晶体结构，长度单位为 bohr。读取这类文件后，`bader` 程序输出的笛卡尔原子坐标也以 bohr 为单位。
