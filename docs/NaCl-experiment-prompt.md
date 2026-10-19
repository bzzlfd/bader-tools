> 让蓝色大肥鱼按照本项目文档，在不联网查阅资料的情况下独立完成 NaCl Bader 实验。

# 实验目标

首先理解本项目，并掌握以下背景知识：

1. Henkelman 课题组的 `bader` 程序，以及使用价电子电荷密度划分 Bader 体积时可能产生的误导；
2. PWmat 电荷密度文件的格式及相关输出；
3. 本项目提供的电荷密度转换与芯电子参考密度功能。

本实验旨在 PWmat 计算结果上复现 Henkelman NaCl 示例所展示的问题，并检验本项目所提出解决方案的有效性。同时，应记录实验过程中发现的项目功能、文档和实验规范问题。

# 实验准则

为了测试本项目的完备性，只许阅读本地材料和从下文允许的官方来源下载实验数据；不许联网搜索或查阅其他参考资料、手册、说明或教程，不然捅死你。

- 不得把现有的 `note/NaCl-experiment.md`、`assets/NaCl-density-path.png` 或既有 `scratch/` 实验输出作为实验依据。必须独立执行分析，并从本次生成的结果中得出结论；既有报告只用于实验完成后的比较和评分。
- 不得在 `/tmp` 中建立实验目录。实验管理须遵循 `docs/experiment-policy.md`，所有中间文件、运行日志和分析数据均应存放在独立的 `scratch/` 实验目录中。
- 不得修改 `example/` 中的原始输入。需要转换、解压或组合输入时，应在本次实验目录中进行。
- 须保留实际执行的命令、软件版本、输入来源和关键中间文件，使结论能够复核。

## 网络环境

联网的目的是取得实验所需材料。从任一允许的官方来源或来源明确的缓存取得有效文件后，即可继续实验，无须恢复原下载来源的访问。允许跟随官方地址的正常重定向，并记录最终来源。

下载失败时，先根据错误信息区分连接、TLS、HTTP 响应或文件校验问题，不得仅凭一次工具报错认定资源不可用。每项缺失资源最多进行一次有针对性的恢复尝试，例如换用命令行下载工具或调整仅影响本次请求的连接参数；不得修改全局网络配置。仍失败时，改用其他允许的来源或缓存，避免反复重试或开展全面网络排障。下载 `chgsum.pl` 等工具失败时，也应先完成上述有限尝试，再考虑提示词允许的替代实现。

若所有允许的来源和可用缓存均无法提供必要材料，应向用户报告缺失材料、错误摘要和已尝试的方法，由用户决定是否进一步检查网络环境；可以继续不依赖该材料的实验步骤。

须统计并在对话中汇报所有联网操作。每次外部请求、重试和重定向均应记录其时间、目的、地址和结果；成功下载的文件还应记录实际来源。

# 实验材料

Henkelman 课题组的 `bader` examples 中有两个 NaCl 算例：`NaCl.tar.gz` 和 `NaCl_wcore.tar.gz`。

- `NaCl.tar.gz` 使用含 9 个价电子的 Na 赝势。压缩包中的主要电荷密度文件为 `CHG_NaCl`，直接执行 `bader` 即可得到合理结果。
- `NaCl_wcore.tar.gz` 使用仅含 1 个价电子的 Na 赝势。`CHGCAR` 中 Na 附近没有电荷密度极大值，电荷密度的梯度流全部流向 Cl，所得结果与全电子参考划分不一致；需要执行 `bader CHGCAR -ref CHGCAR_sum` 进行修正。

实验所需外部材料的获取位置可从本项目的 `note/bader-usage.md` 获得。以下来源均可接受：

- Henkelman 课题组网站：
  - [`NaCl.tar.gz`](https://theory.cm.utexas.edu/henkelman/code/bader/download/NaCl.tar.gz)；
  - [`NaCl_wcore.tar.gz`](https://theory.cm.utexas.edu/henkelman/code/bader/download/NaCl_wcore.tar.gz)；
  - [`chgsum.pl` 所在的 VTST scripts 页面](http://theory.cm.utexas.edu/vtsttools/scripts.html)。
- Henkelman 课题组的官方 GitHub `bader` 仓库：从 `examples/` 目录获取相应压缩包。

若本地已有来源明确的缓存，也可直接使用。须在实验记录中说明实际采用的来源；两个压缩包从某一官方来源下载失败时，可以改用上述另一官方来源，但不得通过联网搜索寻找第三方镜像或其他资料。

实验使用以下材料：

- 【材料 1｜Henkelman Na9】官方 `NaCl.tar.gz`；
- 【材料 2｜Henkelman Na1】官方 `NaCl_wcore.tar.gz`；
- 【材料 3｜PWmat PBE Na9】`example/NaCl.SG15PBE/`；
- 【材料 4｜PWmat PBE Na1】`example/NaCl.zval1.SG15PBE/`；
- 【材料 5｜VASP PBE Na9】`example/NaCl.VASP_Na9Cl7_48/`；
- 【材料 6｜VASP PBE Na1】`example/NaCl.VASP_Na1Cl7_36/`；
- 【材料 7｜PWmat LDA Na1】`example/NaCl.FHILDA/`；
- 【材料 8｜PWmat PBE Na9 SPIN2】`example/NaCl.SG15PBE.SPIN2/`。

各项材料的关系如下：

- 【材料 3】和【材料 4】是 PWmat 计算数据，Na 的价电子划分分别与【材料 1】和【材料 2】对应；
- 【材料 5】和【材料 6】是分别仿照【材料 1】和【材料 2】进行的 VASP 计算。【材料 1】和【材料 2】强制提高了电荷密度网格，而【材料 5】和【材料 6】采用 VASP 默认网格；
- 【材料 7】是 `example/` 中唯一采用 LDA 泛函的 PWmat 材料，其他 PWmat 材料均采用 PBE 泛函；
- 【材料 8】与【材料 3】对应，但启用了共线自旋极化计算，即 `SPIN = 2`。

# 实验内容

## PWmat 数据

对【材料 3｜PWmat PBE Na9】、【材料 4｜PWmat PBE Na1】、【材料 7｜PWmat LDA Na1】和【材料 8｜PWmat PBE Na9 SPIN2】，分别在以下三种条件下执行 `bader` 分析，共计 12 次：

1. 直接使用 PWmat 原始价电子密度；
2. 使用叠加了 Na 芯电子密度的参考密度进行划分；
3. 使用叠加了 Na 和 Cl 芯电子密度的参考密度进行划分。

应使用原始价电子密度作为 `bader` 的积分文件，并通过 `-ref` 指定参考密度。例如：

```bash
bader rho.cube
bader rho.cube -ref rho.ref-na.cube
bader rho.cube -ref rho.ref-nacl.cube
```

参考密度只用于划分 Bader 体积，最终积分的仍是 `rho.cube` 中的价电子密度。因此，不得把参考密度自身的格点积分作为 Bader 电荷或本实验的正确性判据；芯电子数应通过 `.corecharge` 径向表的球对称积分检查。

### 为 FHI LDA 材料构造 ONCVPSP 输入

【材料 7】的 FHI UPF 不含 `<PP_INPUTFILE>`。请分别为 Na 和 Cl 手工构造 ONCVPSP 输入，重新计算 LDA 芯密度。

开始制作输入前，先阅读 `docs/bader-reference-density.md` 的“UPF 中没有 `<PP_INPUTFILE>` 时”，以及本地 ONCVPSP 发行包随附的输入说明和相应示例。重点理解原子电子组态、`nc` / `nv`、`iexc`、参考能量 `ep`、`rc`、`ncon` / `nbas`、投影子和测试组态的设置。记录实际阅读的本地文档路径；若本地缺少说明，应在报告中列为文档缺口，继续依据项目文档和本地输入示例工作，遵守前述联网限制。

按以下顺序制作和检查输入：

1. 从【材料 7】的 UPF 读取价电子数，确定 Na 和 Cl 的电子组态及价—芯划分；核对各轨道占据数之和、芯态行数 `nc` 和价态行数 `nv`。
2. 优先采用本地同元素、同价—芯划分的完整输入作模板：Na 可参考 `example/NaCl.zval1.SG15PBE/Na.z1.ONCV.PBE.UPF`，Cl 可参考 `example/NaCl.SG15PBE/Cl.SG15.PBE.UPF` 中的 `<PP_INPUTFILE>`。模板用于提供完整语法和后续参数，不可把模板中的 PBE 设置当作目标 LDA 设置。
3. 将目标输入设为 LDA，即 `iexc = 3`，逐项检查电子组态和参数含义后再运行。更换泛函后须重新检查参考态及赝势生成参数的适用性，不能假定只改 `iexc` 就一定成功。
4. 分别运行 Na 和 Cl，保存完整输入、标准输出和标准错误。检查输出回显的泛函、电子组态和价—芯划分；同时确认程序正常完成且存在完整 `!R` 数据块，不能只凭进程退出码判断成功。
5. 若失败，先根据日志定位到输入检查、原子全电子求解或后续赝势生成阶段。原子阶段失败时核对物理输入；后续阶段失败时，根据本地文档检查报错通道的 `ep`、`rc`、约束、基组和投影子设置，按错误信息作有依据的调整并保留每次输入与日志。保持目标泛函、电子组态和价—芯划分一致，避免无依据地轮换参数。
6. 从本次成功运行的 `!R` 输出提取新的 `.corecharge`，检查球对称径向积分是否等于相应芯电子数。不得复用【材料 3】、【材料 4】或既有实验中的 PBE `.corecharge`。

本实验只要求取得符合目标原子设置的芯密度，全电子计算之后的参数以程序正常完成并输出 `!R` 为目的。报告中须说明：这里重新计算的是采用相同电子组态、价—芯划分和 LDA 泛函的原子芯密度，并非原 FHI 赝势生成过程的完整复现。

## Henkelman 示例与 VASP 数据

执行以下 7 次分析：

1. 【材料 1｜Henkelman Na9】：仅直接分析 `CHG_NaCl`；全电子参考条件标为“不适用”；
2. 【材料 2｜Henkelman Na1】：直接分析 `CHGCAR`，再执行 `bader CHGCAR -ref CHGCAR_sum`；
3. 【材料 5｜VASP PBE Na9】：直接分析 `CHGCAR`，再使用 `AECCAR0 + AECCAR2` 作为全电子参考；
4. 【材料 6｜VASP PBE Na1】：直接分析 `CHGCAR`，再使用 `AECCAR0 + AECCAR2` 作为全电子参考。

不得自行构造与该计算不匹配的全电子参考。

合并 `AECCAR0` 和 `AECCAR2` 时，使用从上述 VTST scripts 页面获取的 `chgsum.pl`。若该工具不可用，也可根据本地文件格式实现等价求和，但须记录方法，并验证晶格、网格和数据块一致；不得联网寻找其他脚本或教程。

PWmat 部分 12 次、Henkelman 与 VASP 部分 7 次，整个实验共计 19 次可执行的 `bader` 分析。

# 实验报告

实验报告、图片、证据保留和最终交付均须遵循 `docs/experiment-policy.md`。本提示词不另行授权向 `note/`、`assets/` 或其他长期位置写入文件。报告至少应包含实验环境与输入、方法、结果、验证、联网操作记录，以及发现的提示词或项目问题。

## 电荷转移量

按以下定义计算每个 Na 向 Cl 转移的电荷量：

$$
\Delta q_{\mathrm{Na}\rightarrow\mathrm{Cl}}
=z_{\mathrm{val}}(\mathrm{Na})
-\frac{1}{N_{\mathrm{Na}}}\sum_{i\in\mathrm{Na}}N_i^{\mathrm{Bader}}
$$

$\Delta q>0$ 表示 Na 向 Cl 转移电子。须用 Cl 的平均得电子量交叉检查电荷守恒，并报告等价 Na 之间的最大离散度。

使用下面一张汇总表，按【材料 1、2、5、6、3、8、4、7】排列。后三列均为每个 Na 向 Cl 转移的电子数，单位统一为 e/Na；每个数值单元格只填一个转移量。将占位符替换为本次实验数据。

| 材料 | 来源与输入 | 程序 | 泛函 | Na 价电子数 | 网格 | 直接分析 | Na 芯参考 | Na+Cl 芯参考 |
| --- | --- | --- | --- | ---: | --- | ---: | ---: | ---: |
| 【材料 1｜Henkelman Na9】 | `NaCl.tar.gz` 中的 `NaCl/CHG_NaCl` | VASP | 待核实 | 9 | 待读取 | 待填写 | 不适用 | 不适用 |
| 【材料 2｜Henkelman Na1】 | `NaCl_wcore.tar.gz` 中的 `NaCl_wcore/CHGCAR` | VASP | 待核实 | 1 | 待读取 | 待填写 | 不适用 | 待填写 |
| 【材料 5｜VASP PBE Na9】 | `example/NaCl.VASP_Na9Cl7_48/CHGCAR` | VASP | PBE | 9 | 待读取 | 待填写 | 不适用 | 待填写 |
| 【材料 6｜VASP PBE Na1】 | `example/NaCl.VASP_Na1Cl7_36/CHGCAR` | VASP | PBE | 1 | 待读取 | 待填写 | 不适用 | 待填写 |
| 【材料 3｜PWmat PBE Na9】 | `example/NaCl.SG15PBE/OUT.RHO` | PWmat | PBE | 9 | 待读取 | 待填写 | 待填写 | 待填写 |
| 【材料 8｜PWmat PBE Na9 SPIN2】 | `example/NaCl.SG15PBE.SPIN2/OUT.RHO`、`OUT.RHO_2` | PWmat | PBE | 9 | 待读取 | 待填写 | 待填写 | 待填写 |
| 【材料 4｜PWmat PBE Na1】 | `example/NaCl.zval1.SG15PBE/OUT.RHO` | PWmat | PBE | 1 | 待读取 | 待填写 | 待填写 | 待填写 |
| 【材料 7｜PWmat LDA Na1】 | `example/NaCl.FHILDA/OUT.RHO` | PWmat | LDA | 1 | 待读取 | 待填写 | 待填写 | 待填写 |

VASP 材料的直接结果填入“直接分析”列，全电子参考划分结果填入“Na+Cl 芯参考”列；后者在 VASP 行表示 `CHGCAR_sum` 全电子参考，在 PWmat 行表示叠加 Na、Cl 芯密度的参考。最终报告须保留这一表注。

“来源与输入”填写原始来源及实际输入路径或压缩包成员；本次工作目录和参考文件路径可在表下注明。输入未提供某项元数据时，写明“输入未提供”，不要猜测。“不适用”“缺少输入”和“执行失败”必须分别标注，不得统一写成空值。

电荷守恒和等价原子的验证在正文中简述，保留 19 个条件的计算明细，报告最大守恒误差及等价 Na 电荷极差，无须再添加结果表。极差定义为 $\max_i N_i^{\mathrm{Bader}}-\min_i N_i^{\mathrm{Bader}}$。

## Na—Cl 路径电荷密度

绘制以下三张图。所有图的横坐标均为沿最近邻 Na→Cl 路径距 Na 的距离（bohr），纵坐标为电荷密度（$\mathrm{e}/\mathrm{bohr}^3$）。使用线性坐标，纵轴显示范围统一为 0–0.4；超出范围的数据仅由图框裁切，须在图注中说明，不得改写数据或让近核峰值决定自动缩放范围。

### 图 1：【材料 3｜PWmat PBE Na9】

仅绘制以下四组数据，并在图上方标出本材料各通道截断半径：

| 数据来源 | 内容 | 绘图形式 |
| --- | --- | --- |
| `rho.cube` | 原始价电子密度 | 黑色散点（scatter） |
| `rho.ref-nacl.cube` | Na+Cl 芯参考密度 | 红色散点（scatter） |
| Na 的 `.corecharge` | 原始径向芯密度表 | 蓝色无标记实线（line） |
| Cl 的 `.corecharge` | 原始径向芯密度表 | 橙色无标记实线（line） |

### 图 2：【材料 4｜PWmat PBE Na1】

使用与图 1 完全相同的四组数据来源、绘图形式和颜色，但读取【材料 4】本次生成的 cube 和 `.corecharge`，标注其对应 UPF 中的各通道截断半径。

### 图 3：【材料 3｜PWmat PBE Na9】与【材料 4｜PWmat PBE Na1】对照

在一张图中设置上下两个子图（`axes1`、`axes2`），共享横坐标，并采用相同的纵轴显示范围。材料 3 与材料 4 用不同颜色或点形区分，两个子图中的材料样式保持一致。

| 子图 | 数据组 1（散点） | 数据组 2（散点） |
| --- | --- | --- |
| `axes1`：原始价电子密度 | 材料 3 的 `rho.cube` | 材料 4 的 `rho.cube` |
| `axes2`：Na+Cl 芯参考密度 | 材料 3 的 `rho.ref-nacl.cube` | 材料 4 的 `rho.ref-nacl.cube` |

图 3 总共四组数据，仅比较两材料的原始密度与参考密度，不加入 `.corecharge` 曲线、差分密度或截断半径标记。

### 数据读取与图例

所有 cube 数据只读取 Na—Cl 路径实际经过的格点，不作插值，以散点表示。图 1、图 2 无需添加 `rho.ref-na.cube` 或 cube 差分芯密度的散点。

`.corecharge` 忠实使用表中的原始数值：Na 曲线用 $(x,y)=(r,\rho_\mathrm{core})$；Cl 曲线用 $x=d_{\mathrm{Na-Cl}}-r$、$y=\rho_\mathrm{core}$。只保留路径范围内的数据点，并按表中顺序连接相邻点，显式关闭线上的点标记。不得重采样、平滑、拟合或改写数值。

每张图均须独立给出材料名称、数据来源、坐标单位和图例。图 1、图 2 的图例明确写出 cube 格点散点与 `.corecharge` 原始表格实线，不能由前面的结果表列数推断绘图数据组数。

### 图 1、图 2 的逐通道截断半径

从该材料 Na、Cl UPF 的 `<PP_INPUTFILE>` 中，读取 `# PSEUDOPOTENTIAL AND OPTIMIZATION` 段逐角动量通道的 `rc`，分别标注 $s$、$p$、$d$ 通道；输入未包含的通道不添加。这里使用构造输入中的通道半径，不使用 `PP_BETA` 的 `cutoff_radius`，也不只取各通道最大值。

在主图上方放置与横坐标对齐的标记带，按以下位置绘制短竖线：

- Na 通道：$x=rc_{\mathrm{Na},l}$，文字注释放在标记带左侧；
- Cl 通道：$x=d_{\mathrm{Na-Cl}}-rc_{\mathrm{Cl},l}$，文字注释放在标记带右侧。

每条注释写出元素、角动量通道和精确 `rc`（bohr），用引线连接到对应竖线；同元素多个通道的 `rc` 相同时，可共用竖线，但须列全通道名称。文字可分行排列，引线允许交叉，不得为了避开交叉而改变竖线位置。两个原子通道在路径上的范围分别为 $[0,rc_{\mathrm{Na},l}]$ 和 $[d-rc_{\mathrm{Cl},l'},d]$；是否交叠按这些区间判断，即比较 $rc_{\mathrm{Na},l}+rc_{\mathrm{Cl},l'}$ 与 $d$。标记带不覆盖数据区，也不改变主图纵轴范围。

图注须说明：这些是 ONCVPSP 构造输入中的逐通道截断半径，不是 `.corecharge` 的有效尾部截断半径。直接在图内展示通道和半径，无须另列半径结果表。

## 验证与限制

报告至少应验证：

1. 所有预期可执行条件均生成了有效的 `ACF.dat`，失败条件则保留日志并说明原因；
2. PWmat 原始密度积分与相应赝势价电子总数一致；
3. `.corecharge` 的球对称径向积分与预期芯电子数一致；
4. 等价原子的结果离散度以及 Na 失电子量与 Cl 得电子量的差异；
5. 官方示例自带结果与本次重跑结果之间的差异；
6. 任何不能由本项目独立完成、需要近似输入或依赖外部已有工具的步骤。

不同材料之间通常同时改变了程序、赝势、泛函、网格和计算设置。没有控制变量或收敛序列时，不得把材料之间的差异归因于单一因素。
