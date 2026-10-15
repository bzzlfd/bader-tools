# bader-tools 使用说明

## `convert_rho2cube.x`

### 命令格式

```text
convert_rho2cube.x \
  -a ATOMCONFIG \
  -r RHOPATH [WEIGHT] ... \
  -o OUTPUT.cube \
  [-c Z CORECHARGE [QCORE] ...]
```

| 参数 | 含义 |
|---|---|
| `-a PATH`、`--atom PATH` | PWmat 的晶体结构文件，提供晶格、原子序数和分数坐标, 实际文件名需要视情况从 `REPORT` `IN.ATOM` 中找到, 弛豫计算需要使用 `final.config`。 |
| `-r PATH [W]`、`--rho PATH [W]` | 一个 PWmat `OUT.RHO` 及其可选权重，默认 `W=1`；可重复，最多 64 个。 |
| `-o PATH` | 输出 cube 文件。 |
| `-c Z PATH [QCORE]`、`--core-rho Z PATH [QCORE]` | 对原子序数 `Z` 在 `OUTPUT.cube` 上叠加`PATH`指定的芯电子径向密度表。`QCORE` 是可选的, 可以填入用户预期的芯电子数供程序对 `PATH` 中的数据进行校验。 |
| `-h`、`--help` | 打印帮助。 |

程序最终会对读入的所有电荷密度数据按照权重系数累加. 权重可以是负数，因此也可以生成密度差。

为防止混用不同计算的文件,
所有 `OUT.RHO` 必须具有相同的网格、晶格和 `nnodes`。文件元数据不一致时程序会停止。`atom.config` 与 `OUT.RHO` 的晶格矢量差超过某个阈值时，程序也会直接报错退出。


### 芯电子密度文件

`--core-rho` 接受一个文本表。空行以及以 `#` 或 `!` 开头的行会被忽略，每个数据行包含两列：

```text
# r [bohr]    rho_core [e/bohr^3]
0.000000      1.234567890e+02
0.002000      1.230000000e+02
...
```

半径必须严格递增。第二列是实际的球对称径向密度，不包含 `4*pi` 因子：

$$
4\pi\int_0^\infty r^2\rho_\mathrm{core}(r)\,dr=N_\mathrm{core}.
$$

数据结尾的密度及其导数都应接近零；如果最后一点仍非零，程序会警告表格可能被截断。程序对径向表作线性插值，并在晶胞内每个相应元素的原子周围叠加，周期像也会被计入。

可以自己制作满足上述格式的模型密度，但推荐按照 [bader-reference-density.md](./bader-reference-density.md) 使用带本项目补丁的 ONCVPSP 生成可靠数据。

## `run_oncvpsp_from_upf.sh`

该脚本从 ONCVPSP 生成的 UPF 文件的 `<PP_INPUTFILE>` 中提取原始输入，选择相应的 ONCVPSP 程序并重新运行，输出完整报告。此步骤不提取芯电荷，也不要求 ONCVPSP 已应用芯电荷输出补丁。

```bash
tool/run_oncvpsp_from_upf.sh Na.UPF
tool/run_oncvpsp_from_upf.sh Na.UPF -o reports/Na.out
tool/run_oncvpsp_from_upf.sh Na.UPF -o -
```

默认输出到输入文件旁：将 `.UPF` 后缀（不区分大小写）替换为 `.oncvpsp.stdout`；没有该后缀时追加 `.oncvpsp.stdout`。`-o PATH` 指定输出文件，`-o -` 将报告输出到 stdout。报告运行成功后才会发布；指定文件时，脚本在目标目录暂存后替换已有文件。摘要和诊断写入 stderr。

`--oncvpsp PATH` 可以指定可执行文件或安装目录。文件表示直接强制使用指定程序，UPF 类型推断仅作提示；目录表示根据 UPF 的相对论和 SOC 元数据自动选择程序，未知类型或元数据冲突会报错。未指定时先使用非空的 `ONCVPSP_DIR`，再从 `PATH` 查找。编译器运行库、module 等运行环境由调用者准备。

默认在调用目录创建独立的 `.oncvpsp-work.XXXXXX/`，退出时清理，不使用 `/tmp`。`--keep-workdir DIR` 改为在新建的 `DIR` 中运行，并在成功或失败时保留完整现场；`DIR` 必须不存在，父目录必须已存在。

```bash
tool/run_oncvpsp_from_upf.sh Na.UPF --keep-workdir Na-run
```

工作目录包含提取的 `oncvpsp.in`、完整或不完整的 `oncvpsp.stdout`、`oncvpsp.stderr`，以及 ONCVPSP 创建的其他文件。输入提取失败时可能只有不完整的输入文件。正式报告另行发布，保留目录中的报告副本不会被移走。

## `extract_oncv_corecharge.sh`

该脚本从已有 ONCVPSP 报告提取芯电荷表，输出两列：半径 `r [bohr]` 和全电子芯密度 `rho_core [e/bohr^3]`。它会除去 ONCVPSP 数据中的 `4*pi` 因子，但不会运行生成器。

```bash
tool/extract_oncv_corecharge.sh Na.oncvpsp.stdout
tool/extract_oncv_corecharge.sh reports/Na.out -o Na.corecharge
tool/extract_oncv_corecharge.sh Na.oncvpsp.stdout -o -
```

文件输入默认将 `.oncvpsp.stdout` 后缀替换为 `.corecharge`；其他文件名直接追加 `.corecharge`。无输入参数或输入为 `-` 时从 stdin 读取，此时必须显式指定 `-o PATH` 或 `-o -`。摘要、积分和警告写入 stderr。

`--tag auto|R|r` 选择数据块：

- `auto`（默认）：优先 `!R`；没有 `!R` 数据时回退到 `!r`，并警告。
- `R`：要求补丁输出的 `!R` 数据，不回退。这是制作可靠芯密度时的推荐选择。
- `r`：读取 `!r` 绘图数据。其网格经过稀疏化，密度可能被裁剪，所得芯电荷积分可能偏低。

验证成功后才发布结果；损坏的 `!R` 数据不会触发自动回退。文件输出在目标目录暂存后替换；stdout 输出在调用目录暂存，不使用 `/tmp`。强制选择 `R` 或 `r` 时忽略另一数据块。`--source-upf PATH` 只在表头记录来源，不读取 UPF 或改变数据。

推荐分两步生成并保留可复查的报告：

```bash
tool/run_oncvpsp_from_upf.sh Na.UPF \
  --oncvpsp /path/to/oncvpsp/bin \
  -o Na.oncvpsp.stdout

tool/extract_oncv_corecharge.sh Na.oncvpsp.stdout \
  --tag R \
  --source-upf Na.UPF \
  -o Na.corecharge
```

也可以通过管道只保存最终芯电荷表：

```bash
set -o pipefail
tool/run_oncvpsp_from_upf.sh Na.UPF -o - |
  tool/extract_oncv_corecharge.sh \
    --source-upf Na.UPF \
    -o Na.corecharge
```

使用 `-o PATH` 可以在计算或验证失败时保护已有结果；shell 的 `> PATH` 会提前截断文件，不能提供同样的保护。

## `rho_integral.py`

这个辅助程序直接积分一个或多个 PWmat `OUT.RHO`，适合在转换前检查文件、电子数和网格：

```bash
python3 tool/rho_integral.py OUT.RHO
python3 tool/rho_integral.py OUT.RHO OUT.RHO_2
```

它会分别打印每个文件的网格、晶胞体积、积分电子数、密度最小值和最大值。程序依赖 Python 3 和 NumPy；它只读取和报告，不修改输入文件，也不会自动把多个文件相加。

## 不同情况的使用示例

### 非自旋极化计算

在包含 `atom.config` 和 `OUT.RHO` 的 PWmat 计算目录中运行：

```bash
/path/to/bader-tools/build/convert_rho2cube.x \
  -a atom.config -r OUT.RHO -o rho.cube
bader rho.cube
```

`bader` 的主要结果写入 `ACF.dat`。更详细的 `bader` 参数、算法和输出格式见 [bader-usage.md](../note/bader-usage.md)。

### 共线自旋极化计算（`SPIN=2`）

PWmat 把两个自旋通道分别写在 `OUT.RHO` 和 `OUT.RHO_2` 中。Bader 分析需要总电子密度，因此两个通道的权重都应为 `1`：

```bash
/path/to/bader-tools/build/convert_rho2cube.x \
  -a atom.config \
  -r OUT.RHO 1 \
  -r OUT.RHO_2 1 \
  -o rho.cube
bader rho.cube
```

不要写成两个 `0.5`，除非确实想得到两通道的平均值。

### 生成密度差

使用负权重可以在相同的晶格和网格上计算两份密度之差：

```bash
convert_rho2cube.x \
  -a atom.config \
  -r OUT.RHO.new 1 \
  -r OUT.RHO.reference -1 \
  -o density-difference.cube
```

### 使用芯电子参考密度

假设已经为 Na 和 Cl 准备好 `Na.corecharge`、`Cl.corecharge`：

```bash
/path/to/bader-tools/build/convert_rho2cube.x \
  -a atom.config \
  -r OUT.RHO \
  -o rho.cube \
  --core-rho 11 Na.corecharge 10 \
  --core-rho 17 Cl.corecharge 10

bader rho.cube -ref rho.ref.cube
```

这里的 `11`、`17` 是原子序数；末尾的 `10` 是可选的每原子预期芯电子数 `QCORE`。这个例子对应 Na 使用 1 个价电子、Cl 使用 7 个价电子的赝势，所以两者都有 `QCORE = Z - z_valence = 10`。如果赝势采用不同的价电子划分，应相应修改该数值，例如含 9 个价电子的 Na 应使用 `QCORE=2`。

程序仍把原始加权价电子密度写入 `rho.cube`，并自动把“价电子 + 芯电子”写入 `rho.ref.cube`。推荐使用：

```bash
bader rho.cube -ref rho.ref.cube
```

这样由参考密度决定空间划分，但 `ACF.dat` 中积分的仍是 `rho.cube` 的价电子密度，不应把参考密度直接作为待积分密度。

## 结果检查与常见问题

- 转换日志中的密度积分应与赝势价电子总数一致。`SPIN=2` 时，应检查两个通道积分之和。
- `ACF.dat` 中的 `CHARGE` 是每个 Bader volume 内从 `rho.cube` 积分得到的电子数。使用赝势密度时，电荷转移应以各元素的赝势价电子数为参照，而不是直接用原子序数相减。
- `--core-rho` 只改变参考划分文件，不改变 `rho.cube` 中实际积分的价电子密度。
- 同一条命令中的多个 `OUT.RHO` 必须来自相同晶胞和相同 FFT 网格；程序不会对不同网格做插值。
- 芯密度表必须与所用赝势的价/芯电子划分一致。`QCORE=Z-z_valence` 是很有用的校验值，但只产生警告，不会替用户决定数据是否物理可靠。
- ONCVPSP 未应用 [`oncvpsp-patch/run_plot.patch`](../oncvpsp-patch/run_plot.patch) 时通常只有为绘图裁剪过的 `!r` 数据。脚本允许回退以便诊断，但正式结果建议使用补丁产生的 `!R` 数据并通过 `--tag R` 强制检查。
