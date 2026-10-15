# bader-tools 程序与工具使用参考

本文完整说明本项目提供的程序和辅助工具。有关 PWmat 文件格式的细节，参见 [file-format.md](../note/file-format.md)；有关 Bader 分析的基本用法，参见 [bader-usage.md](../note/bader-usage.md)；有关近似全电子参考密度的制作流程，参见 [bader-reference-density.md](bader-reference-density.md)。

## 工具概览

| 程序或脚本 | 主要输入 | 主要输出 | 功能 |
| --- | --- | --- | --- |
| `convert_rho2cube.x` | PWmat 结构文件、一个或多个 `OUT.RHO`，以及可选的芯电子密度表 | Gaussian cube 文件 | 对电荷密度作加权求和，可选叠加芯电子密度，并转换为 cube 格式。 |
| `run_oncvpsp_from_upf.sh` | ONCVPSP 生成的 UPF 文件 | ONCVPSP 计算报告 | 提取 UPF 中保存的生成器输入，选择合适的 ONCVPSP 程序并重新运行。 |
| `extract_oncv_corecharge.sh` | ONCVPSP 计算报告 | `.corecharge` 芯电子密度表 | 提取 `!R` 或 `!r` 径向数据，除去 $4\pi$ 因子并检查积分。 |


## `convert_rho2cube.x`

### 功能与命令格式

`convert_rho2cube.x` 读取 PWmat 的结构和实空间电荷密度，将一个或多个 `OUT.RHO` 的加权和写成 Gaussian cube 文件。指定 `--core-rho` 时，程序还会在输出前叠加相应元素的球对称芯电子密度。

```text
convert_rho2cube.x \
  -a ATOMCONFIG \
  -r RHOPATH [WEIGHT] ... \
  -o OUTPUT.cube \
  [-c Z CORECHARGE [QCORE] ...]
```

| 参数 | 含义 |
| --- | --- |
| `-a PATH`、`--atom PATH` | PWmat 结构文件，提供晶格、原子序数和分数坐标。只能指定一次。 |
| `-r PATH [WEIGHT]`、`--rho PATH [WEIGHT]` | PWmat `OUT.RHO` 及其可选权重；默认权重为 `1`。可以重复指定。 |
| `-o PATH` | 唯一的输出 cube 文件。只能指定一次。 |
| `-c Z PATH [QCORE]`、`--core-rho Z PATH [QCORE]` | 为原子序数 `Z` 的元素叠加 `PATH` 中的芯电子密度。`QCORE` 是可选的预期每原子芯电子数。可以对不同元素重复指定。 |
| `-h`、`--help` | 打印帮助信息并退出。 |

`-a`、至少一个 `-r` 和 `-o` 都是必需参数。同一原子序数不能重复指定 `--core-rho`。`Z` 必须是正整数；`QCORE` 必须是有限的非负数。

### 结构与电荷密度输入

应使用与 `OUT.RHO` 对应的结构。静态计算通常使用实际参与计算的 `atom.config`；结构弛豫后应使用最终结构，例如 `final.config`。具体文件名需要结合 PWmat 的 `IN.ATOM` 和 `REPORT` 确认。

程序按下式直接组合所有 `OUT.RHO`：

$$
\rho_\mathrm{mix}(\boldsymbol r)=\sum_i w_i\rho_i(\boldsymbol r).
$$

利用权重可以完成很多操作, 比如使用负权重生成密度差；两个权重均为 `0.5` 用于求平均。

第一个 `OUT.RHO` 决定输出网格。其余文件必须具有相同的三个网格维数、`nnodes` 和晶格；结构文件与 `OUT.RHO` 的晶格也必须一致。晶格矩阵任一分量的差值超过 $10^{-5}$ angstrom 时，程序停止，不进行网格插值。

### 芯电子密度表格式

`--core-rho` 接受纯文本径向表。空行以及以 `#` 或 `!` 开头的行会被忽略；每个数据行包含半径和芯电子密度两列：

```text
# r [bohr]    rho_core [e/bohr^3]
0.000000      1.234567890e+02
0.002000      1.230000000e+02
...
```

半径 $r$ 的单位是 bohr，且必须严格递增；密度 $\rho_\mathrm{core}(r)$ 的单位是 $\mathrm{e}/\mathrm{bohr}^3$，不包含 $4\pi$ 因子。文件至少需要两个数据点，密度不能处处为零。球对称积分为

$$
4\pi\int_0^\infty r^2\rho_\mathrm{core}(r)\,\mathrm{d}r=N_\mathrm{core}.
$$

程序采用线性插值：小于第一个采样半径时使用第一个密度值；达到有效截断半径后取零。有效截断半径是最后一个满足 $|\rho_\mathrm{core}|>10^{-10}/(4\pi)$ 的采样半径。最后一个数据点仍超过该阈值时，程序会警告表格可能被截断，并输出末尾最多五个数据点及其数值导数供检查。

对每个 `--core-rho`，程序将插值后的密度叠加到晶胞中所有原子序数为 `Z` 的原子周围，并计入周期像。如果结构中没有对应元素，程序报错退出。

指定 `QCORE` 时，程序把径向积分与该值比较。二者之差超过以下容差时只给出警告，不会停止计算：

$$
\max\bigl(0.001\ \mathrm{e/atom},\;0.1\%\times Q_\mathrm{core}\bigr).
$$

`QCORE` 通常取原子序数与赝势价电子数之差，即 $Q_\mathrm{core}=Z-z_\mathrm{valence}$。

可以自行制作满足上述约定的模型密度；正式分析推荐按照 [bader-reference-density.md](bader-reference-density.md) 使用应用了本项目补丁的 ONCVPSP 生成数据。

### 输出与运行信息

每次调用只写出 `-o` 指定的一个 cube 文件。输出网格沿用 `OUT.RHO` 的网格，cube 文件中的长度使用 bohr，密度保持 $\mathrm{e}/\mathrm{bohr}^3$；结构坐标由分数坐标和晶格换算得到。

输出文件已存在时，程序会询问是否覆盖，只有输入 `y` 或 `Y` 才继续。程序不会隐式生成 `.ref.cube` 或其他文件。

运行时会报告：

- 结构中的原子数和晶格；
- 每个 `OUT.RHO` 的权重、网格、`nnodes` 和未乘权重的独立积分；
- 每个芯电子密度表的点数、有效截断半径、径向积分和尾部数据；
- 未指定 `--core-rho` 时，输出混合密度的积分、最小值和最大值；
- 指定 `--core-rho` 时，输出密度的最小值和最大值，但不报告网格积分。

芯电子密度在原子核附近高度集中，常规实空间网格通常无法准确积分，因此指定 `--core-rho` 后不报告输出的网格积分。芯电子数应以径向表的积分为准。

## `run_oncvpsp_from_upf.sh`

### 功能与命令格式

该脚本从 ONCVPSP 生成的 UPF 文件中提取 `<PP_INPUTFILE>`，选择相应的 ONCVPSP 可执行文件，重新运行原子计算，并保存生成器的标准输出。它不提取芯电子密度，也不修改 UPF。脚本本身不要求 ONCVPSP 应用本项目补丁；只有后续需要完整 `!R` 数据时才需要补丁版程序。

```text
tool/run_oncvpsp_from_upf.sh FILE.UPF [OPTIONS]
```

| 参数 | 含义 |
| --- | --- |
| `FILE.UPF` | 包含完整 `<PP_INPUTFILE>` 数据块的 UPF 文件。只接受一个。 |
| `-o PATH`、`--output PATH` | 把 ONCVPSP 报告写入 `PATH`；`-` 表示 stdout。 |
| `--oncvpsp PATH` | 指定一个可执行文件，或指定用于自动选择可执行文件的安装目录。 |
| `--keep-workdir DIR` | 在新建的 `DIR` 中运行并永久保留工作文件；`DIR` 必须尚不存在，父目录必须存在。 |
| `-h`、`--help` | 打印帮助信息并退出。 |

没有指定 `-o` 时，脚本将输入文件名末尾的 `.UPF`（不区分大小写）替换为 `.oncvpsp.stdout`；输入名没有该后缀时则直接追加 `.oncvpsp.stdout`。

### ONCVPSP 程序选择

脚本结合 `<PP_HEADER>` 的 `relativistic`、`has_so` 以及结构化 SOC 量子数判断所需程序。它忽略 `<PP_INFO>` 中的描述性文本，也能识别 PWmat 使用 `10`、`20`、`30` 表示 SOC 通道的约定。

自动选择时使用以下文件名：

| 推断类型 | 依次尝试的可执行文件 |
| --- | --- |
| 标量相对论（`scalar`） | `oncvpsp.x` |
| 全相对论（`full`） | `oncvpspr.x`、`oncvpsp_r.x` |
| 非相对论（`nonrelativistic`） | `oncvpspnr.x`、`oncvpsp_nr.x` |

可执行文件的查找顺序如下：

1. `--oncvpsp FILE`：直接使用该文件。此时类型推断仅供提示，即使元数据未知或冲突也允许运行。
2. `--oncvpsp DIR`：在该目录中按推断类型选择程序。
3. 非空环境变量 `ONCVPSP_DIR`：在该目录中按推断类型选择程序。
4. `PATH`：查找推断类型对应的程序。

这是来源优先级，而不是逐级失败回退：一旦 `--oncvpsp DIR` 或 `ONCVPSP_DIR` 生效，在该目录中找不到所需程序就会报错。除直接指定可执行文件外，UPF 类型必须能够唯一确定，且元数据不能互相冲突，否则脚本停止并要求使用 `--oncvpsp FILE` 明确选择。编译器运行库、module 和其他运行环境由调用者预先准备，脚本不会修改环境。

### 工作目录、输出与失败行为

默认情况下，脚本在调用目录创建权限受限的 `.oncvpsp-work.XXXXXX/`，并在退出时删除，不使用 `/tmp`。使用 `--keep-workdir DIR` 后，无论成功或失败，目录都会保留，其中可能包含：

- `oncvpsp.in`：从 `<PP_INPUTFILE>` 提取的生成器输入；
- `oncvpsp.stdout`：完整或不完整的标准输出；
- `oncvpsp.stderr`：标准错误；
- ONCVPSP 生成的其他文件。

UPF 中没有完整的 `<PP_INPUTFILE>` 时，脚本停止。由 `upf2upfSO` 转换的 PWmat SOC 赝势通常省略该数据块，因而不能直接重跑；可按照 [bader-reference-density.md](bader-reference-density.md) 手工恢复输入。

ONCVPSP 的运行时限为 300 秒。超时、程序无法启动或非零退出都会使脚本失败。ONCVPSP 的 `stderr`、类型推断、程序选择、工作目录和发布摘要都写入 `stderr`。

输出路径不能与输入 UPF 指向同一文件。脚本只有在 ONCVPSP 成功退出后才发布报告：文件输出先在目标目录暂存，再替换同名文件；失败不会截断已有结果；`-o -` 也会等运行成功后再把完整报告写到 `stdout`。使用 `--keep-workdir` 时，工作目录中的报告副本会继续保留，正式输出不会把它移走。

## `extract_oncv_corecharge.sh`

### 功能与命令格式

该脚本从已有的 ONCVPSP 报告中提取全电子芯密度，除去 ONCVPSP 数据包含的 $4\pi$ 因子，并生成 `convert_rho2cube.x --core-rho` 可以读取的 `.corecharge` 文件。它不会运行 ONCVPSP。

```text
tool/extract_oncv_corecharge.sh [ONCV_OUTPUT|-] [OPTIONS]
```

| 参数 | 含义 |
| --- | --- |
| `ONCV_OUTPUT` | ONCVPSP 计算报告。省略或指定为 `-` 时从 `stdin` 读取。 |
| `-o PATH`、`--output PATH` | 把芯电子密度表写入 `PATH`；`-` 表示 `stdout`。 |
| `--tag TAG` | 选择数据块；`TAG` 可以是 `auto`（默认）、`R` 或 `r`，也可以写成 `!R` 或 `!r`。 |
| `--source-upf PATH` | 在输出表头记录来源 UPF 的路径；只写入元数据，不读取该文件。 |
| `-h`、`--help` | 打印帮助信息并退出。 |

文件输入未指定 `-o` 时，脚本将末尾的 `.oncvpsp.stdout` 替换为 `.corecharge`；其他文件名则直接追加 `.corecharge`。从 `stdin` 读取时必须显式指定 `-o PATH` 或 `-o -`。

### 数据块选择与检查

`--tag` 的三种模式如下：

- `auto`：优先使用 `!R`；只有报告中完全没有 `!R` 数据行时才回退到 `!r`，并给出警告。损坏或只有一个数据点的 `!R` 不会触发回退。
- `R`：只读取补丁版 ONCVPSP 输出的 `!R` 数据，不允许回退。这是制作正式结果时的推荐模式。
- `r`：只读取用于绘图的 `!r` 数据，其中第一列是半径，第三列是芯密度。

原始 `!r` 数据可能经过网格稀疏化和密度裁剪：当芯密度达到 `max(5*rho, rhomod)` 时，报告中的值会被该上限替代，部分靠近原点的行还会被丢弃。因此，从 `!r` 得到的芯电子积分可能偏低。有关补丁版 `!R` 数据的生成方法，参见 [bader-reference-density.md](bader-reference-density.md)。

脚本要求所选数据块至少包含两个数据点，并检查半径和密度是有限数、半径非负且严格递增。输出密度等于 ONCVPSP 报告中的芯密度除以 $4\pi$。脚本使用梯形积分计算

$$
4\pi\int r^2\rho_\mathrm{core}(r)\,\mathrm{d}r,
$$

并把所选数据块、数据范围和积分写入 `stderr`，同时把来源、列定义和积分写入输出表头。

### 输出安全性

脚本在完整解析并验证报告后才发布结果。文件输出先在目标文件旁暂存，再替换同名文件；`stdout` 输出也会先暂存在调用目录中，因此无效输入不会产生半截结果。诊断、摘要和警告均写入 `stderr`。

输出路径不能与输入报告或 `--source-upf` 指向同一文件。直接使用脚本的 `-o PATH` 可以保护已有结果；shell 的 `> PATH` 会在脚本开始前截断文件，不具备相同的失败保护。

## 组合使用示例

以下示例假定 `convert_rho2cube.x` 已在 `PATH` 中；也可以改用完整路径 `/path/to/bader-tools/build/convert_rho2cube.x`。

### 非自旋极化计算

```bash
convert_rho2cube.x \
  -a atom.config \
  -r OUT.RHO \
  -o rho.cube

bader rho.cube
```

`bader` 的主要结果写入 `ACF.dat`。

### 共线自旋极化计算（`SPIN=2`）

PWmat 将两个自旋通道分别写在 `OUT.RHO` 和 `OUT.RHO_2` 中。Bader 分析需要总电子密度，因此两个通道的权重都应为 `1`：

```bash
convert_rho2cube.x \
  -a atom.config \
  -r OUT.RHO 1 \
  -r OUT.RHO_2 1 \
  -o rho.cube
```

不要把两个权重写成 `0.5`，除非确实需要两个通道的平均值。

### 生成密度差

```bash
convert_rho2cube.x \
  -a atom.config \
  -r OUT.RHO.new 1 \
  -r OUT.RHO.reference -1 \
  -o density-difference.cube
```

所有输入仍须具有相同的晶格和网格。

### 从 UPF 生成芯电子密度表

推荐分两步运行，以保留可复查的 ONCVPSP 报告：

```bash
tool/run_oncvpsp_from_upf.sh Na.UPF \
  --oncvpsp /path/to/oncvpsp/bin \
  -o Na.oncvpsp.stdout

tool/extract_oncv_corecharge.sh Na.oncvpsp.stdout \
  --tag R \
  --source-upf Na.UPF \
  -o Na.corecharge
```

如果不需要保留中间报告，可以用管道直接连接两个脚本。这也是二者有意支持的 Unix/Linux 命令行用法：`run_oncvpsp_from_upf.sh -o -` 把完整报告写入 `stdout`，运行信息和诊断仍写入 `stderr`；`extract_oncv_corecharge.sh` 省略输入文件时从 `stdin` 读取报告，再通过 `-o` 发布芯电子密度表。若下游程序也能从 `stdin` 读取，还可以为提取脚本指定 `-o -`，继续通过管道传递结果。

```bash
set -o pipefail
tool/run_oncvpsp_from_upf.sh Na.UPF -o - |
  tool/extract_oncv_corecharge.sh \
    --tag R \
    --source-upf Na.UPF \
    -o Na.corecharge
```

`set -o pipefail` 可以让 ONCVPSP 重跑失败时整条管道返回失败状态。

### 使用芯电子参考密度

假设已经为 Na 和 Cl 准备好 `Na.corecharge` 和 `Cl.corecharge`：

```bash
convert_rho2cube.x \
  -a atom.config \
  -r OUT.RHO \
  -o rho.cube

convert_rho2cube.x \
  -a atom.config \
  -r OUT.RHO \
  -o rho.ref.cube \
  --core-rho 11 Na.corecharge 10 \
  --core-rho 17 Cl.corecharge 10

bader rho.cube -ref rho.ref.cube
```

这里的 `11` 和 `17` 是原子序数；两个 `10` 是可选的每原子预期芯电子数。这个例子假定 Na 赝势包含 1 个价电子、Cl 赝势包含 7 个价电子，因此二者均有 $Q_\mathrm{core}=Z-z_\mathrm{valence}=10$。如果使用不同的价、芯电子划分，应相应修改；例如，含 9 个价电子的 Na 应使用 `QCORE=2`。

两次转换的 `-a`、`-r` 及权重必须完全相同；除输出路径外，第二次只额外指定 `--core-rho`。`rho.ref.cube` 用于决定 Bader volume，`ACF.dat` 中积分的仍是 `rho.cube` 的赝价电子密度，不应把参考密度直接作为待积分密度。

## 结果检查与常见问题

- 未指定 `--core-rho` 时，转换程序报告的输出积分应与输入权重所对应的赝势价电子总数一致。`SPIN=2` 时，总密度使用两个通道积分之和。
- 指定 `--core-rho` 时，应使用径向表的积分检查芯电子数，不要用 cube 网格对尖锐的芯电子密度作定量积分。
- `ACF.dat` 中的 `CHARGE` 是每个 Bader volume 内从待积分文件获得的电子数。分析赝势密度时，应以各元素的赝势价电子数为参照计算电荷转移，而不是直接用原子序数相减。
- `--core-rho` 只改变本次调用中 `-o` 指定的输出；程序不会隐式生成其他文件。
- 芯电子密度表必须与实际使用的赝势采用相同的价、芯电子划分。`QCORE` 只提供警告性质的交叉检查，不能代替对赝势来源和物理设置的确认。
- 正式结果应使用补丁版 ONCVPSP 的 `!R` 数据，并通过 `--tag R` 禁止意外回退到经过稀疏化和裁剪的 `!r` 数据。
