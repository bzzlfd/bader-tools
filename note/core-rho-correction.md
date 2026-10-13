在 [bader 用法](bader-usage.md)的“尝试示例”小节中, 我们提到 Henkelman 课题组网站提供的 [NaCl_wcore](https://theory.cm.utexas.edu/henkelman/code/bader/download/NaCl_wcore.tar.gz) 例子需要全电子电荷密度的参考才能进行可靠的 Bader charge 划分. 

在赝势程序中, 输出的电荷密度格点数据只包含 (1)光滑化的 (2)价电子[^valencecore] 贡献, 满占据的、局域的芯电子态对成键以及某些物理过程贡献不大，被假设为冻结，并在输出中被舍弃[^cross]。这样的好处，一方面是可以通过减少电子态加速对角化求解过程，一方面是（几乎）完备地表达光滑的电子态需要很少数量的平面波/稀疏的实空间网格, 这也可以提高计算速度。

[^valencecore]: 当然，定义哪部分是价电子, 哪部分是芯电子也是人为的. 

[^cross]: 刻下的话语浮现心头。"将我的芯电子, 弃置于此. ". 

Bader charge 以电荷密度的梯度流作为划分依据. 可是舍弃了芯电子电荷密度贡献，电荷密度梯度当然也会改变。
NaCl_wcore 的例子就可以理解为过于激进的价-芯电子分配, 以及只包含价电子贡献的梯度信息给 Bader volume 划分带来的困扰. 

在 VASP PAW 赝势上解决这个问题不需要对基础设施做任何修改, PAW 本身就带有"全电子"信息, 只需要输出出来, 让 `bader` 以全电子电荷密度为参考, 执行 `bader CHGCAR -ref CHGCAR_sum` 就好了. 
然而对于 NCPP 来说, 全电子是不需要的, 赝势文件和DFT计算中通常不包含这部分, 想简单重走VASP路线, PWmat办不到的. 但NCPP终究是从全电子来的. 
如果硬要 "重建全电子电荷分布",  我想应该会是这样
## 严格的做法

对于所有 PWmat 的**占据态**赝价电子波函数 $\psi^\text{Ps}_{m\bm{k}}$, 通过某个原子的赝价电子 $\phi^\text{Ps}_{nl}$, 投影子 $\beta_{nl}$, 全电子 $\phi^\text{AE}_{nl}$  重建其全电子电荷密度, 应该有

$$
\rho^\text{AE} = 
\sum_{
    \begin{subarray}{c} 
        nl\\
        n\in \text{core} \\
    \end{subarray}
} |\phi^\text{AE}_{nl}|^2
+
\sum_{
    \begin{subarray}{c} 
        m\bm{k}, nl \\
        m \in \text{occ.}, n\in \text{val.} \\
    \end{subarray}
} |\psi^\text{Ps}_{m\bm{k}} + \left( \phi^\text{AE}_{nl} - \phi^\text{Ps}_{nl} \right) \braket{\beta_{nl}|\psi^\text{Ps}_{m\bm{k}}} |^2
{,}
$$

其中第一项的含义叠加芯电子电荷密度, 第二项的含义是把占据态赝势价波函数按照投影比例换成全电子价波函数. 
第二项的投影写法应该是正确的, 因为 Vanderbilt 形式的 separable NCPP 中 

$$
\left(\varepsilon_{nl} -T -V_\text{loc} \right) \ket{ \phi_{nl} }\braket{\beta_{nl}|\psi}
$$

的含义就是 $\psi$ 投影到 $\beta_{nl}$ 的部分, 应该感受到和这个赝价电子态  $\phi^\text{Ps}_{nl}$ 一样的散射. 

假设使用的赝势文件是通过 ONCVPSP [^oncvpsp] 生成的. 
为了重建参考全电子电荷密度, 我需要

1. 重构 oncvpsp 源码, 以输出
    1. 全部全电子波函数 $\phi^\text{AE}_{nl}$, 赝价电子波函数 $\phi^\text{Ps}_{nl}$
    2. oncvpsp 对角化 $B$ 矩阵前, 未经线性组合的 $\beta_{nl}$
2. 考虑过滤 oncvpsp 中的束缚态/散射态波函数
3. 实现 $\braket{\beta_{nl}|\psi^\text{Ps}_{m\bm{k}}}$ 的计算

[^oncvpsp]: 它事实上或许已经成为现代模守恒赝势的标准生成程序, 很多广泛使用的高精度赝势项目 (SG15, PD) 都是由它产生的. 现在应该很少有人用其他软件生成的赝势了吧. 

然后还要教用这套复杂的工具, 强制用户使用 oncvpsp赝势. 想必非常折磨, 折磨我也折磨用户. 


因为冻芯电子近似, 第一项仅仅是叠加一个万年不变的函数. 
因为NCPP在截断半径 $r_{cl}$ 之外的 $\phi^\text{Ps}_{nl}=\phi^\text{AE}_{nl}$ , 第二项影响范围应该只局限在  $r_{cl}$ 以内. 
和老师讨论的过程中, 我们认为芯电子区域 ($r<r_{cl}$) 的电荷密度对 Bader volume 划分影响不大, 或许可以换成以下

## 简单且 (大概) 等效的替代做法

$$
\rho^\text{AE} = 
\sum_{
    \begin{subarray}{c} 
        nl\\
        n\in \text{core} \\
    \end{subarray}
} |\phi^\text{AE}_{nl}|^2
+
\sum_{
    \begin{subarray}{c} 
        m\bm{k} \\
        m \in \text{occ.} \\
    \end{subarray}
} |\psi^\text{Ps}_{m\bm{k}}|^2
{.}
$$

我只需要

1. 用任意赝势生成程序的全电子计算过程, 产生 $\rho_\text{core}^\text{AE} (r)=\sum_{
        nl \in \text{core} \\
} |\phi^\text{AE}_{nl}|^2$
2. 把 $\rho_\text{core}^\text{AE} (r)$ 叠加到价电子电荷密度文件, 作为 `-ref` 输入

$\rho_\text{core}^\text{AE} (r)$ 甚至直接在 oncvpsp 的标准输出中存在, ~~都不需要改 oncvpsp~~ (emm, 那个数据是服务于画图的, 在横轴纵轴都被截断了, 不是完整数据, 还是要改oncvpsp代码). 

这是我们的最终方案. 
