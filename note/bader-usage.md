Bader 定义了一种以电荷密度梯度流将分子划分为原子的方式, 这种划分可以用作电荷分析. 
一些 DFT 软件输出的电荷密度数据是以实空间均匀格点上浮点数数值表示的, 
Henkelman 针对这种电荷密度数据形式, 发明了一种高效的 Bader volume 划分算法. 

该算法的实现程序 `bader` 可以在[Henkelman的课题组网站下](https://theory.cm.utexas.edu/henkelman/code/bader/)或[github](https://github.com/henkelmangroup/bader)找到,  
课题组网站中还包含了源码/可执行文件下载, 程序说明, 输入实例, 对 VASP/CASTEP 用户的提醒, 论文列表. 

本文会结合论文和代码, 对该程序的使用做一些解释, 希望能够对初次接触, 对该程序的使用踌躇不定的人提供一些帮助. 
本文可能不会覆盖所有内容, 但在现在的 coding agent 时代, 源码是最好的程序行为说明, 你可以凭着兴趣继续探索. 

# 编译和安装
`bader` 的 Fortran 源码/可执行程序可以从[官网](https://theory.cm.utexas.edu/henkelman/code/bader/download/bader.tar.gz)或[github](https://github.com/henkelmangroup/bader)下载

这本身不是一个有复杂依赖的 Fortran 程序, 在 bader 源码中 Makefile 的同级目录下运行
```bash
make bader
```
就可以在源码目录编译出一个 `bader` 可执行文件. 

看你的目录组织方式了, 我更喜欢
```bash
PATH=$HOME/.local/bin:$PATH
ln -s bader $HOME/.local/bin/bader
```
让 Linux `PATH` 环境变量能找到 `bader`. 
任何问题都可以试着问问 LLM . 

## 尝试 examples 
官网或[github](https://github.com/henkelmangroup/bader/tree/main/examples) 也可以找到 examples, 每个 example 压缩包中一般包括电荷密度输入文件 (`CHG_*`) 和`bader`分析的输出文件`ACF.dat`, `BCF.dat`, `BVF.dat` . 
可以解压一个压缩包并进入其目录 (如 `C2H4a`), 运行 `bader <chargefile>` (如 `bader CHG_C2H4a`), 就可以得到结果; 

其中 `NaCl_wcore` 压缩包较为特别, 它除了输入电荷密度文件 CHGCAR, 还有一个 CHGCAR_sum, 这是

1. 在 INCAR 中设置 `LAECHG=.TRUE.`
2. 运行 VASP 输出全电子电荷密度文件 `AECCAR0`, `AECCAR1`, `AECCAR2` 
3. 使用 Henkelman 提供的脚本 [chgsum.pl](http://theory.cm.utexas.edu/vtsttools/scripts.html) 执行 `chgsum.pl AECCAR0 AECCAR2` 合并

得到的文件. 可以以该文件作为 "全电子" 电荷密度参考, 执行 `bader CHGCAR -ref CHGCAR_sum` 进行更可靠的空间划分和电荷积分. 即, 空间划分在 `CHGCAR_sum` 数据中进行, 电子密度积分在 `CHGCAR` 中进行. 
使用 `-ref` 在这个例子中的效果是, 在使用前, Na 原子的一个价电子不会在 Na 原子附近产生任何峰值, bader 划分会让电荷密度梯度全都流到 Cl 原子上; 使用 `-ref` 引入全电子划分参考后, Na 原子附近会保留一些电子数. 其结果可以与 `NaCl.tar.gz` (Na原子有9个价电子的计算结果) 比较. 

注意不要直接执行 `bader CHGCAR_sum` , 因为全电子电荷密度变化很剧烈, `CHGCAR` 的实空间网格密度太稀疏无法准确描述, 最直接的后果是对 `CHGCAR_sum` 以黎曼求和的方式积分, 无法准确得到全电子电子数. 

# 软件使用

## 直接使用

直接运行
```bash
bader
```
会打印简短的程序 usage 

运行 
```bash
bader -h
```
可以对 usage 中出现的参数进行更详细的解释

如果想要用它分析电荷密度文件, 最简单的命令是
```bash
bader <chargefile>
```
程序本身可以推断区分所传入的文件格式, 是 GUASSIAN的 .cube, 还是 VASP4或VASP5 的 CHGCAR

```bash
bader <chargefile> -i <cube|chgcar> 
```
可以强行指定使用以哪种程式读取输入文件. 
如果一次运行程序涉及多个 <chargefile> 格式的输入输出, 它们的格式是相同的. 

```bash
bader <chargefile> -ref <reference_charge>
```
可以以 `<reference_charge>` 为参考划分 bader volume 区域, 然后在划分结果上用 `<chargefile>` 数据进行电子密度积分. 

## 选择例程 (`-c`/`-n`)
`bader` 程序有两种划分方式的例程 

1. 以原子位置和电荷密度为参考的bader划分例程 
2. 仅以原子位置为参考的voronoi划分例程

程序内部有两个布尔变量`bader_flag`和`voronoi_flag`, 分别独立控制两个划分例程的开关. 
`-c`/`-n` 参数的目的, 就是把相应的布尔变量设成 `.true.`/`.false.`,

默认情况下
```fortran
bader_flag = .true.
voronoi_flag = .false.
```
如果输入
```bash
bader <chargefile> -n voronoi -c voronoi -c voronoi -n bader -c bader 
```
最后的状态是
```fortran
bader_flag = .true.
voronoi_flag = .true.
```

考虑到 `bader` 的主线是 bader划分, 该程序的几乎所有参数只对 bader划分例程有影响, 结果分析的输出文件也只由 bader划分例程产生. 
所以我们可以把 voronoi 看待为该程序的附带功能, 接下来的讨论会忽视它. 

## 选择算法 (`-b`)

`-b` 的选项有 `ongrid`, `neargrid` 和 `weight`, 每个选项都与一篇论文对应, 
对应关系可以参照下表, 具体算法介绍可以参考下一章

|      论文       |   `-b`   |
| :-----------: | :------: |
| Henkelman2006 |  ongrid  |
| Sanville2007  | ~~offgrid~~  |
|   Tang2009    | neargrid |
|    Yu2011     |  weight  |

- Henkelman2006 是 Henkelman 提出原始高效算法的论文; 
- Sanville2007 指出 Henkelman 算法中会将自由电荷密度梯度吸附到附近26($3^3-1$)个格点上, 甚至会使得该算法甚至会表现出所分析出的电荷转移量依赖于分子取向的结果. 但他们所提出的修正方法较为复杂, 在当前代码中被弃用; 
- Tang2009 针对 Sanville2007 提出的问题, 在 Henkelman2006 的基础上引入一个修正向量, 简单且有效地解决了 Sanville2007 提出的问题; 
- 而 Yu2011 有更理论的出发点, 在他们的视角下, 每个格点 (或认为是 voxel) 可以自然地按照比例的归属多个 basin. 

算法选择推荐 `neargrid` 或 `weight`:
- neargrid 是默认算法, 计算很快, 修正方法简单且有效; 但是算法是过程依赖的, 不同的过程可能导致最终得到的划分也不同. 所以这个例程会在划分完成后又引入 refine 子例程, 完善*边界*格点归属 (*边界*指的是该格点存在一个近邻格点, 该格点与其近邻格点的归属不同).  
    - `-r` 可以控制refine例程, 这个参数在历史上发生了多次变化. 过去曾经尝试的设计包括
        - `-r N`, `N` 是正整数, 表示重新 refine 几次边界点; `N=0`, 表示关闭 refine
        - `-r <-1|-2|auto>`, `auto` 被解析为 `-1`; 它们都会重复refine, 直到某次发现 refine后需要变更 basin所属的格点数量变成 0 ; `-1` 和 `-2` 的区别是 `-2` 每轮都重新检查所有边界点, `-1` 则是在每轮仅检查上一轮被重置的格点的3×3×3邻域. refine 算法可能有死循环的风险, 这时候可以退回到 `-r N`
        - 后来 `-r 0` 被设置为执行一次 refine 后退出
        - 而现在 1.05 版本中 , refine 的逻辑被改为无论如何只 refine 一次, 这样一来 `-r <-1|-2>` 的区别也消失了. 
    - 一般算法在找到已有所处的格点后就会停止, 对应默认参数 `-m known`, 这是该算法线性scaling的来源; 也可以通过 `-m max` 让flow直到找到basin的极大值点才停止, 这种设置下最终结果在数学上是唯一的. 
- weight 更优雅, 数学上得到的 bader volume 划分是唯一的, 天然不会遇到 Sanville2007 指出的问题, 但是计算会更耗时一些. 


## 输出
除了在 `stdout` 打印计算进度以外, `bader` 还会默认输出 3 个文件: `ACF.dat`, `BCF.dat`, `AVF.dat`
- `ACF.dat`: 可以读到每个原子 bader volume 划分下电荷积分数, 是一般用户关心的文件. 
- `BCF.dat`: 每个原子附近可能有多个极值点 (这尤其在赝势程序是普遍的情况, 价电子电荷密度在周围一圈), 所以 `bader` 程序是以极值点划分basin volume; 然后在就近把这些极大值对应到原子上, 把 basin volume 合并成一个原子 bader volume. 这个文件汇总了 basin 信息. 可以注意到这里的数据一般比 `ACF.dat` 中的多. 
- `AVF.dat`: 为了显示 basin 和 atom 的对应关系, `BCF.dat` 文件记录了每个 basin 属于哪个 atom; 该文件则是反过来, 记录了每个 atom 中有哪些 basin. 


### `-p` 
> "我想看看 bader volume 的表面" 
> 
> --- 识别并绘制表面需要花一些功夫, 但是 `bader` 里对每个格点都进行了染色 (这个格点属于哪个 atom, 哪个 basin), 你可以直接查看某个 atom/basin 下都有哪些格点, 通过观察它的空间占据脑补 bader volume 的表面形状.  

这就是 `-p` 参数的作用, 它会控制 `bader` 输出格点数据, 输出文件格式与输入文件相同. 
可以想见每个文件都很大, 所以只有当明确 `-p` 指定时才会写出这些文件. 

`-p` 有很多选项, 这里会介绍以下选项 
```
-p < atom_index | bader_index >
-p < all_atom | all_bader >
-p < sel_atom | sel_bader > <volume list or range>
-p < sum_atom | sum_bader > <volume list or range>
```

1. `atom/bader_index` 后面不接受参数, 会输出一个 .cube/CHGCAR 格式格点文件, 每个格点记录的是这个格点属于哪个 Atom/Basin index. 
2. `all_atom/bader` 后面不接受参数, 直接输出全部文件
    1. 输出内容为每个 Atom/Basin 划分体积内的电荷密度分布, 每个划分输出一个 .cube或CHGCAR 格式文件 (取决于输入文件格式) . 
	2. `bader <chargefile> -p all_atom -p all_bader` 便是终极全面, 终极占硬盘存储空间的输出参数口牙. 
3. `sel_atom/bader` 不同于 `all`, 会有选择地输出; 而 `sum` 的处理与 `sel` 类似, 只不过会求和后只输出一个文件
	1. 后面可以跟的合法参数示例:
		1. `-p sel_atom 1`
		2. `-p sel_atom 1 3 5`
		3. `-p sel_atom 1-3`
    2. 未定义行为, 导致程序崩溃的参数示例: 
        1. `-p sel_atom 1 2-3`
        2. `-p sel_atom 9-5`
        3. `-p sel_atom 1-2 -p sel_atom 3` (对 allocated 数组再次 allocate)

> "如果我 `bader CHGCAR -p sel_atom 1-3 -p all_atom -p sum_atom 4 8`会如何? " 
>
> --- 请看 VCR
> 
> ```fortran
> ! bader/options_mod.f90
>     opts%print_sel_atom = .TRUE.
>     opts%selanum = 3
>     ALLOCATE(opts%selavol(opts%selanum))
>     opts%selavol = [1, 2, 3]
>     ! |
>     opts%print_all_atom = .TRUE.
>     ! |
>     opts%print_sum_atom = .TRUE.
>     opts%sumanum = 2
>     ALLOCATE(opts%sumavol(opts%sumanum))
>     opts%sumavol = [4, 8]
> 
> ! bader/main.f90
>      IF (opts%print_all_bader) CALL write_all_bader(bdr,opts,ions,chgval)
>      IF (opts%print_all_atom) CALL write_all_atom(bdr,opts,ions,chgval)
>      IF (opts%print_sel_atom) CALL write_sel_atom(bdr,opts,ions,chgval)
>      IF (opts%print_sel_bader) CALL write_sel_bader(bdr,opts,ions,chgval)
>      IF (opts%print_sum_atom) CALL write_sum_atom(bdr,opts,ions,chgval)
>      IF (opts%print_sum_bader) CALL write_sum_bader(bdr,opts,ions,chgval)
>      IF (opts%print_bader_index) CALL write_bader_index(bdr,opts,ions,chgval)
>      IF (opts%print_atom_index) CALL write_atom_index(bdr,opts,ions,chgval)
> ```
> 
> 所以会是先输出所有原子的划分网格数据, 然后再输出 1-3 号原子划分网格数据 (覆盖已经存在的 1-3 号原子网格数据文件), 然后再输出 4 8 号原子网格划分合并后的网格数据. 


# 算法


## 定义
说实话我没搞懂 `bader` 源码中对 bader volume 的定义, 行文中的用词有可能和 Henkelman 课题组的习惯有所不同. 
所以在此提醒读者, 我会接下来使用以下术语来指代 `bader` 算法中的某些概念 (当然, 这些术语在本文较早的时候就被使用了)

![图1, 来自Tang2009](../assets/Tang2009_1.png)

### *flow*
在 Bader 的定义中, 空间某点沿着的电荷密度的梯度流动, 最终会停在某个极大值点. 
我们定义这条流线为一个 *flow*. 

对于离散网格的情况, 如上图(a), 我们让空间点在网格上移动, 每一步移动的目标是近邻格点中电荷密度数值上升最快的方向. 这样的移动会在近邻格点电荷密度无法上升时 (到达极大值点) 停下来, 这时候得到一条连线 (如上图(a) 中的 flow1), 我们称为离散网格版本的 *flow*. 

可以注意到, 在这样的算法下, 接下来的 flow 无需直到到达电荷密度极大值才停下来, 当它发现它走到其他 flow 走过的路径上, 它就已经知道自己最终会流到哪个极值点了. 如上图(a) 中的 flow2. 

### *basin*
当所有点都知道自己最终会流到哪个极大值点, 我们便完成了对空间网格的划分. 

我们把划分后的每个区域成为一个 *basin*, 意为流汇聚的地方. (嗯, 水往低处流, 但是这里的 flow 往高处流)

### *bader volume*
极大值点可能会比原子更多, 接下来我们需要决定每个 *basin* 属于哪个原子, 将属于相同原子的 *basin* 合并后的体积, 我们称为这个原子的 *bader volume*[^badervolume].

[^badervolume]: 我使用的 *basin* 大约对应 Henkelman 课题组语境下的 *bader volume*


## [Henkelman2006](10.1016/j.commatsci.2005.04.010)
有了上述定义后, 我们现在可以介绍 Henkelman2006 的算法了. 
哦, 在上面的定义已经把算法讲完了. 
因为基本上每个格点都只触及一次, 随着体系的增加, 算法计算时间也是随之线性增加的, 这是非常高效的算法. 

你会发现这个算法过程中, 空间点移动方向只能在 26 个方向中选择, 真实梯度方向会"吸附"到这26个方向中. 
[Sanville2007](10.1002/jcc.20575) 论文中指出, 这样的离散化+格点移动算法会带来极大的电荷积分误差, 
分子的bader charge分析中甚至会表现出分子取向的依赖性, 这是不物理的. 
增加网格密度也无法有效改善这种情况. 
官网提供的 examples 中, C2H4a C2H4b 两个压缩包便可以说明此问题. 

## [Tang2009](10.1088/0953-8984/21/8/084204) 
![图2, 来自Tang2009](../assets/Tang2009_2.png)
图中 (a) 展示了 Henkelman2006 算法因为移动方向吸附导致的 basin 划分错误, 图 (b) 展示了 Tang2009 的修正方法: 随着格点移动, 同时记录一个梯度方向 $\vec{r}_\text{grad}$ 与移动方向 $\vec{r}_\text{grid}$ 之间的偏离矢量 $\Delta \vec{r}=\Delta \vec{r}_1$ , 每次移动都累计偏离矢量 ($\Delta \vec{r}=\Delta \vec{r}_1+\Delta \vec{r}_2$), 积累的偏离量会在足够大的时候改变原本算法的移动方向 (correction step), 并重新积累偏移矢量 $\Delta \vec{r}={\Delta \vec{r}_2}'$. 

这样一来, 虽然我们依旧在格点间移动, 但是已经几乎是按照真实的电荷密度梯度方向移动了. 

不过这个方法稍有瑕疵的地方是, 初始移动时偏离误差从 0 开始积累, 最终结果可能会取决于初始格点的选择, 划分结果不是唯一的. 
该算法会在 Basin 划分完成后, 针对边界格点进行 refine 缓解这个问题. 

## [Yu2011](10.1063/1.3553716)
该论文从更理论的角度出发. 
考察初始时一个 voxel 内均匀分布的点, 在沿着电荷密度梯度概率流守恒地流动后, 最终会到达哪些极大值点. 
从连续空间点到离散格点的离散化过程, 一个格点到另一个格点的流量, 是 voronoi 剖分下的该格点 voxel 多面体对应面的通量. 

这个定义下, 一个格点不必属于某个 basin, 而是可以自然按照流量大小属于多个 basin. 
通过给格点划分引入了 weight 的概念, 可以唯一地确定划分. 
通过分析这个离散化过程中做了什么近似, 可以指出该算法bader charge计算值与真实值之间的误差 与网格密度精度的 阶数关系. 
该算法也可以很容易地扩展到非均匀网格上. 

具体算法实现中, 会先对电荷密度值排序, 然后从大到小逐格点审查. 这样等价于从每个 basin 极大值点出发, 向外流动, 自然地分配basin归属权重, 依旧 (准)线性scaling, 非常妙. 


# `ACF.dat`, `BCF.dat`, `AVF.dat` 每列含义

以下对应 Bader 1.05 的输出例程 `bader_mod.f90` 中的 `bader_output`. `ACF.dat` 按原子汇总, `BCF.dat` 按 basin 列出, `AVF.dat` 记录原子与 basin 的对应关系.

## `ACF.dat`

| 列 | 表头 | 含义 | 源码变量 |
|---|---|---|---|
| 1 | `#` | 原子编号，从 1 开始，与输入文件的原子顺序一致 | `i` |
| 2–4 | `X Y Z` | 原子的笛卡尔坐标 | `ions%r_car(i,:)` |
| 5 | `CHARGE` | 分配给该原子的所有 basin 中的电子密度积分 | `bdr%ionchg(i)` |
| 6 | `MIN DIST` | 原子到其所属区域边界格点的最短距离，考虑周期性边界 | `bdr%minsurfdist(i)` |
| 7 | `ATOMIC VOL` | 分配给该原子的所有 basin 的总体积 | `bdr%ionvol(i)` |

注意, `CHARGE` 是输入文件电子密度的积分结果, 不是原子的全电子电荷量或电荷转移量. bader 本身也不清楚
1. 输入文件是否是全电子数据
2. 每个原子原始的价电子/芯电子配置

## `BCF.dat`

| 列 | 表头 | 含义 | 源码变量 |
|---|---|---|---|
| 1 | `#` | 筛选后连续编号的 basin 序号，从 1 开始 | `bdimsig` |
| 2–4 | `X Y Z` | 该 basin 的密度极大值点的笛卡尔坐标 | `bdr%volpos_car(i,:)` |
| 5 | `CHARGE` | 该 basin 内的积分电子数 | `bdr%volchg(i)` |
| 6 | `ATOM` | 该 basin 被分配给的原子编号，对应 `ACF.dat` 第一列 | `bdr%nnion(i)` |
| 7 | `DISTANCE` | 该极大值点到所分配原子的距离，考虑周期性边界 | `bdr%iondist(i)` |


## `AVF.dat`

| 部分 | 表头或内容 | 含义 | 源码变量 |
|---|---|---|---|
| 第一项 | `Atom` | 原子编号，对应 `ACF.dat` 第一列 | `i` |
| 分隔符 | `...` | 固定的排版分隔符 | 无 |
| 后续各项 | `Volume(s)` | 属于该原子的 basin 编号列表，对应 `BCF.dat` 第一列 | `rck(1:cc)` |

```text
   Atom                     Volume(s)
     5   ...       6    7    8    9
```

如果一个原子没有 basin 被划归其中, 则不会出现在这个文件里.

## 单位与文件之间的关系

| 量 | 标准 VASP `CHGCAR` 输入 | 标准 Gaussian cube 输入 |
|---|---|---|
| 坐标与距离 | Å | bohr |
| 体积 | Å³ | bohr³ |
| `CHARGE` | 电子数 | 电子数 |
