VASP
本身网格很密集, 我设成默认 NGXF 之后重跑

Henkelman 提供的 examples 
其中 NaCl.tar.gz 和 NaCl_wcore.tar.gz 文件的区别是, 前者 Na 赝势以 $2s^2 2p^6 3s^1$ 为价电子, 后者以 $3s^1$ 为价电子. 
直接分析 NaCl_wcore.tar.gz 中的 CHGCAR 会得到 Na 的电子全都转移给 Cl 的结果, 是一个展示以全电子电荷密度为参考 -ref 进行bader volume划分修正的例子. 
