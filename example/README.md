# PWmat 示例数据

本目录提供四组 NaCl 计算数据，用于演示和检查 `OUT.RHO` 到 Gaussian
cube 的转换：

| 目录 | 赝势与计算设置 | 电荷密度文件 |
| --- | --- | --- |
| `NaCl.FHILDA/` | FHI LDA；Na 取 1 个、Cl 取 7 个价电子 | `OUT.RHO` |
| `NaCl.SG15PBE/` | SG15 PBE；Na 取 9 个、Cl 取 7 个价电子 | `OUT.RHO` |
| `NaCl.SG15PBE.SPIN2/` | SG15 PBE，共线自旋极化 | `OUT.RHO`、`OUT.RHO_2` |
| `NaCl.zval1.SG15PBE/` | PBE；Na 取 1 个、Cl 取 7 个价电子 | `OUT.RHO` |

每个目录同时保留生成该密度时使用的 `atom.config`、`etot.input` 和
UPF 赝势，便于核对结构、计算设置及价电子数。`OUT.RHO` 是 PWmat
二进制文件，不适合作为文本查看。

`etot.input` 记录的是原始计算环境，其中 `IN.PSP*` 使用原有的上级目录
相对路径。若要重新运行 PWmat 计算，需要先根据当前文件位置调整这些路径。
