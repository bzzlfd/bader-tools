本文介绍如何利用 ONCVPSP 的全电子计算数据, 对 PWmat 在模守恒赝势计算下输出的 (赝价电子) 电荷密度文件 (`OUT.RHO`) 进行全电子修正,
以支持 `bader` 分析 VASP `CHGCAR` 时, 类似引入全电子电荷密度文件 `AECCAR` 辅助 Bader volume 划分 (`bader <CHGCAR> -ref <AECCAR>`) 的功能.

该功能所解决的问题和实现方案的讨论可以查看[笔记 core-rho-correction.md](../note/core-rho-correction.md).

## 使用 ONCVPSP 产生芯电子电荷密度

我们需要一个执行 DFT 原子全电子计算的程序, 从中获得芯电子的电荷密度数据.
赝势生成软件是一个好选择. 因为原子全电子计算是制造赝势的前置动作, 所以它们内部一定包含  DFT 原子全电子计算模块.

我们需要告诉这个计算模块

1. 使用的泛函 (如, LDA/GGA)
2. 电子配置 (如, $1s^2 2s^2 2p^6 3s^1$)
3. 把哪些能级当作芯电子能级 (如, 把 $1s^2 2s^2 2p^6$ 当作芯电子), 以便输出 "芯电子电荷密度"

目前 PWmat 官网提供的 UPF 赝势文件大多由 ONCVPSP 生成, 这类赝势文件在文件开头包含 ONCVPSP 输入, 自然包含了上面三个信息.
把 UPF 文件中 `<PP_INPUTFILE>` 标签下的输出传给 oncvpsp (这个具体的程序可能是 `oncvpsp.x` 或 `oncvpspr.x`, 取决于这个赝势文件考虑了标量相对论效应, 还是全相对论效应(包含自旋轨道耦合)), oncvpsp 就会输出芯电子电荷密度.

`tool/run_oncvpsp_from_upf.sh` 脚本可以帮你从 UPF 中提取 `<PP_INPUTFILE>` 标签并运行 `oncvpsp.x` 或 `oncvpspr.x`.
`tool/extract_oncv_corecharge.sh` 脚本可以帮你从 oncvpsp 的输出中提取芯电子电荷密度.

提取出芯电子电荷密度表 `<ele.corecharge>` 后, 用 `convert_rho2cube.x` 生成 "全电子参考电荷密度"文件供 `bader` 分析:

```bash
convert_rho2cube.x -a atom.config -r OUT.RHO -o rho.cube
convert_rho2cube.x -a atom.config -r OUT.RHO -o rho.ref.cube \
    --core-rho Z_ELE1 ele1.corecharge \
    --core-rho Z_ELE2 ele2.corecharge
bader rho.cube -ref rho.ref.cube
```

其中 `Z_ELE1`、`Z_ELE2` 替换为相应元素的原子序数, `ele1.corecharge`、`ele2.corecharge` 也视情况替换为真实文件.

### 如果 UPF 文件头没有 `<PP_INPUTFILE>` 标签
那就只好自己从头构造一个 oncvpsp 的了. 
一个输入文件大概长这样

```text
# ATOM AND REFERENCE CONFIGURATION
# atsym  z   nc   nv     iexc    psfile
  Si 14.00    3    2       3      upf
#
#   n    l    f
    1    0    2.00
    2    0    2.00
    2    1    6.00
    3    0    2.00
    3    1    2.00
#
# PSEUDOPOTENTIAL AND OPTIMIZATION
......
```

示例只展示了输入文件开头的原子与参考组态, 后面还必须继续给出赝势优化、局域势、投影子、模型芯电荷和测试组态等参数. 这一部分各字段的含义如下:

以 `#` 开头的行是供人阅读的标题、列名或分隔行, 不是计算参数. 例如 `# ATOM AND REFERENCE CONFIGURATION` 和 `# PSEUDOPOTENTIAL AND OPTIMIZATION` 标明数据块的用途, `# atsym ...` 和 `# n l f` 标明各列的含义, 单独的 `#` 只用于视觉分隔. ONCVPSP 会在读取特定数据块前跳过连续的 `#` 行, 因此这些行不会影响原子计算或 `rhoc`. 但 `#` 不是在任意位置都生效的通用注释语法: 例如程序会连续读取 `nc+nv` 个轨道记录, 不应在这些 `(n,l,f)` 记录中间插入 `#` 行.

| 字段 | 含义和对计算的影响 |
|---|---|
| `atsym` | 长度最多为 2 的元素符号. ONCVPSP 只检查它是否非空, 不检查它是否与 `z` 匹配. 它会被写入 UPF 的 `element` 等元数据, 但不决定输出文件名; 文件名由调用程序的脚本和重定向方式决定. |
| `z` | 核电荷数 $Z$, 也就是元素的原子序数, 不是电子数. 它给出核库仑势 $-Z/r$; 最终 Kohn-Sham 有效势还要加上 Hartree 势和交换关联势. |
| `nc` | 芯轨道态的行数, 不是芯电子数. |
| `nv` | 价轨道态的行数, 不是价电子数. |
| `iexc` | 原子 DFT 计算使用的交换关联泛函编号. |
| `psfile` | 赝势输出格式: `psp8` 用于 ABINIT, `upf` 用于 Quantum ESPRESSO/PWSCF, `both` 则两种都输出. ONCVPSP 实际把相应数据块写入标准输出, 再由脚本提取成赝势文件. |

`nc+nv` 决定后面读取的 `(n,l,f)` 记录数. 前 `nc` 行被当作芯轨道, 后 `nv` 行被当作价轨道. `n` 和 `l` 分别是主量子数和角动量量子数, `f` 是该轨道的占据数. 芯电子数和价电子数应分别按占据数求和:

$$
N_\mathrm{core}=\sum_{i=1}^{n_c}f_i,\qquad
N_\mathrm{valence}=\sum_{i=n_c+1}^{n_c+n_v}f_i.
$$

所有占据数的和不必等于 `z`. ONCVPSP 允许

$$
\sum_i f_i\leq Z.
$$

等号表示中性参考原子; 小于 $Z$ 表示正离子参考组态; 大于 $Z$ 会被程序判定为负离子并停止. `f` 本身是实数, 因此可以使用分数占据. `z` 在输入和求解器中也是实数, 但分数 `z` 表示分数核电荷的模型原子, 不是普通元素的离子. 例如要构造 $\mathrm{Si}^{+}$, 应保持 `z=14` 并将总占据数改为 13, 而不是把 `z` 改为 13.

ONCVPSP 的内置 `iexc` 编号为:

| `iexc` | 交换关联泛函 | 类型 |
|---:|---|---|
| `1` | Wigner exchange-correlation | LDA |
| `2` | Hedin--Lundqvist exchange-correlation | LDA |
| `3` | Perdew--Zunger 对 Ceperley--Alder 数据的参数化 | LDA |
| `4` | Perdew--Burke--Ernzerhof (PBE) | GGA |

仅使用 `iexc=1`--`4` 时, ONCVPSP 使用自带的泛函实现, 编译时不需要链接 libxc. 负数 `iexc` 则按 `-XXXCCC` 编码调用 libxc, 其中 `XXX` 和 `CCC` 分别是 libxc 的 exchange 和 correlation 泛函编号. 例如 `-001009` 表示 Perdew--Zunger/Ceperley--Alder LDA, `-101130` 表示 PBE. UPF 写出器只能翻译其中一部分编号; 在当前源码中, `iexc=1` 也没有对应的 UPF 泛函名称, 因此 `iexc=1` 与 `psfile=upf` 的组合会在写出 UPF 时停止.

示例中的前 3 个状态为 $1s^2 2s^2 2p^6$, 共有 10 个芯电子; 后 2 个状态为 $3s^2 3p^2$, 共有 4 个价电子. 总占据数为 14, 所以这是中性 Si 参考原子. 赝势的离子价电荷为

$$
Z_\mathrm{ion}=Z-N_\mathrm{core}=14-10=4.
$$

ONCVPSP 先用上述核电荷、占据数和 `iexc` 自洽求解原子 Kohn--Sham 方程, 得到各轨道的全电子波函数和本征值. 输入记录只有 `(n,l,f)` 三项; `energy (Ha)` 是 ONCVPSP 求解后在输出回显中追加的本征值, 不是需要手工给出的输入参数. 然后程序才根据后续参数构造赝波函数和赝势. `nc` 的分段同时决定哪些全电子轨道累加到本项目要提取的芯电荷密度中.

## 应用补丁, 重新编译 ONCVPSP

ONCVPSP 原本输出的 `!r` 中包含的芯电子电荷密度只为绘图使用, 会在横轴和纵轴裁剪数据网格, 这有利于更好地在图片中展示结果, 却不利于我们利用它进行"全电子"电荷密度修正. 
本项目的 [run_plot.patch](../oncvpsp-patch/run_plot.patch) 会让 oncvpsp 额外输出 `!R` 数据块. 该数据块保留 ONCVPSP 的原始径向网格和未裁剪的芯电荷密度, 供 `extract_oncv_corecharge.sh` 提取.

下面使用 ONCVPSP 和 libxc 的官方源码, 通过 CMake 在用户目录下完成编译和安装. 如果只使用内置的 `iexc=1`--`4`, 可按后文说明跳过 libxc. ONCVPSP 还需要 Fortran/C 编译器、CMake、BLAS 和 LAPACK. `gnuplot` 只用于 ONCVPSP 的交互式绘图, 不是提取芯电荷所必需的. 集群环境通常需要先加载编译器、CMake、BLAS/LAPACK 模块; Debian/Ubuntu 上对应的开发包通常是 `gfortran`、`cmake`、`libblas-dev` 和 `liblapack-dev`.

以下命令在同一个空目录中执行. `install_root` 可以改成任意有写权限的持久目录. 示例固定使用 libxc 7.1.2; 换用其他稳定版本时, 应重新执行后面的编译和验证. 本节已用 ONCVPSP 提交 `dc150ab47d` 和 libxc 7.1.2 验证.

```bash
bader_tools=/absolute/path/to/bader-tools
install_root=$PWD/local

git clone --depth 1 --branch 7.1.2 \
    https://gitlab.com/libxc/libxc.git libxc-7.1.2
git clone https://github.com/oncvpsp/oncvpsp.git oncvpsp
```

如果只使用内置的 `iexc=1`--`4`, 可省略第一条 libxc 的克隆命令和下一小节, 直接获取 ONCVPSP 源码.

### 编译 libxc (仅负数 `iexc` 需要)

ONCVPSP 不仅需要 libxc 的 C 库, 还需要它的 Fortran 接口. libxc 的 CMake 配置默认不构建该接口, 因此 `-DENABLE_FORTRAN=ON` 不能省略. 这里使用静态库, 使最终的 ONCVPSP 程序不必在运行时查找 `libxc.so` 和 `libxcf03.so`.

```bash
cmake -S libxc-7.1.2 -B build-libxc \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$install_root/libxc" \
    -DENABLE_FORTRAN=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TESTING=OFF
cmake --build build-libxc --parallel
cmake --install build-libxc

"$install_root/libxc/bin/xc-info" 1 | head
```

最后一条命令应打印 libxc 的版本以及编号为 1 的 LDA exchange 泛函信息. 安装目录中还应同时存在 `libxc.a`、`libxcf03.a` 和 `xc_f03_lib_m.mod`. 如果使用共享库 (`-DBUILD_SHARED_LIBS=ON`), 则还要把 `$install_root/libxc/lib` 加入系统的运行时库搜索路径, 或在编译 ONCVPSP 时设置合适的 RPATH.

### 检查并应用 oncvpsp 补丁

进入 ONCVPSP 源码目录, 先用 `git apply --check` 检查补丁是否与所下载的源码版本兼容. 前面设置的 `bader_tools` 是本项目源码的绝对路径.

```bash
cd oncvpsp
git apply --check "$bader_tools/oncvpsp-patch/run_plot.patch"
git apply "$bader_tools/oncvpsp-patch/run_plot.patch"
git diff --check
cd ..
```

若第一条命令失败, 不要强行使用 `patch --fuzz`: 上游的 `run_plot.f90` 或 `run_plot_r.f90` 很可能已经改变, 应先检查差异并确认补丁仍然在 `rhoc` 生成之后输出相同含义的数据. `git diff -- src/run_plot.f90 src/run_plot_r.f90` 可以查看实际修改.

### 编译 ONCVPSP

需要使用负数 `iexc` 时, 按下面的方式链接前面编译的 libxc:

```bash
cmake -S oncvpsp -B build-oncvpsp \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$install_root/oncvpsp" \
    -DLibxc_ROOT="$install_root/libxc" \
    -DONCVPSP_WITH_TOML=OFF
cmake --build build-oncvpsp --parallel
cmake --install build-oncvpsp
```

如果只使用内置的 `iexc=1`--`4`, 则无需下载和编译 libxc, 配置 ONCVPSP 时显式关闭它即可:

```bash
cmake -S oncvpsp -B build-oncvpsp \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$install_root/oncvpsp" \
    -DONCVPSP_WITH_Libxc=OFF \
    -DONCVPSP_WITH_TOML=OFF
cmake --build build-oncvpsp --parallel
cmake --install build-oncvpsp
```

这种构建会使用 ONCVPSP 的 `exc_libxc_stub.f90`. `iexc=1`--`4` 不会调用该 stub; 如果输入负数 `iexc`, 程序会报错说明当前可执行文件未链接 libxc, 然后停止.

选择链接 libxc 时, 配置阶段应明确显示 `Found Libxc` 以及实际版本. 如果报 `Libxc ... lacks the required Fortran03 interface`, 通常是编译 libxc 时漏掉了 `-DENABLE_FORTRAN=ON`. 如果找不到 BLAS/LAPACK, 应安装对应的开发包或通过集群模块提供它们; 必要时可按本机安装位置向 CMake 传入 `LAPACK_ROOT`.

ONCVPSP 的 CMake 配置会从 GitHub 下载固定校验和的 `CPM.cmake`; 即使这里关闭了不需要的 TOML 输入支持, 首次配置仍需能够访问 GitHub. `-DONCVPSP_WITH_TOML=OFF` 可以避免继续下载和编译 `toml-f`.

当前 CMake 构建会安装三个程序:

- `oncvpsp.x`: 标量相对论版本;
- `oncvpspnr.x`: 非相对论版本;
- `oncvpspr.x`: 全相对论版本.

某些旧版源码把后两个程序命名为 `oncvpsp_nr.x` 和 `oncvpsp_r.x`. `run_oncvpsp_from_upf.sh` 能识别这两套名称. 可以让脚本通过 `ONCVPSP_DIR` 找到本次安装:

```bash
export ONCVPSP_DIR="$install_root/oncvpsp/bin"
"$ONCVPSP_DIR/oncvpsp.x" --help
```

### 验证 `!R` 输出

不要只检查程序是否成功链接; 至少运行一个带芯电子的原子输入, 确认补丁数据可以被本项目脚本读取. ONCVPSP 自带的 Si 测试含 10 个芯电子:

```bash
"$ONCVPSP_DIR/oncvpsp.x" \
    < oncvpsp/tests/data/14_Si.dat \
    > Si.oncvpsp.stdout

grep -m 1 '^!R ' Si.oncvpsp.stdout
"$bader_tools/tool/extract_oncv_corecharge.sh" \
    Si.oncvpsp.stdout --tag R -o Si.corecharge
grep -F '# 4*pi*int' Si.corecharge
```

最后打印的积分应接近 `10`. 由于数值积分和有限径向网格, 末位可以有很小误差; 本节验证得到 `10.000060`. 如需检查全相对论分支, 可用 `oncvpspr.x` 运行 `oncvpsp/tests/data/52_Te.dat`, 并同样确认输出包含 `!R` 行.

补丁为标准输出新增了大量 `!R` 行, 而上游测试的参考输出不包含这些行. 因此直接运行 `ctest --test-dir build-oncvpsp` 时, 文本比较会在第一条 `!R` 处报差异; 这不等于原子计算失败. 本节验证中, 删除新加的 `!R` 行后, ONCVPSP 的 26 个上游参考输出比较全部通过.

随后即可按照前一节运行实际 UPF, 并要求提取脚本只接受补丁提供的精确数据:

```bash
"$bader_tools/tool/run_oncvpsp_from_upf.sh" Ele.UPF \
    --oncvpsp "$ONCVPSP_DIR"
"$bader_tools/tool/extract_oncv_corecharge.sh" \
    Ele.oncvpsp.stdout --tag R --source-upf Ele.UPF \
    -o Ele.corecharge
```

源码和进一步说明见 [ONCVPSP 官方仓库](https://github.com/oncvpsp/oncvpsp)、[ONCVPSP 项目网站](http://www.mat-simresearch.com/)、[libxc 官方仓库](https://gitlab.com/libxc/libxc) 和 [libxc 下载页](https://libxc.gitlab.io/download/).
