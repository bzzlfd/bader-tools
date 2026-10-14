## rho2cude



## run_oncvpsp_from_upf.sh

从 ONCVPSP UPF 文件的 `<PP_INPUTFILE>` 提取生成输入，选择相应的 ONCVPSP 程序并重新运行，输出完整报告。此步骤不提取芯电荷，也不要求 ONCVPSP 已应用芯电荷输出补丁。

```bash
tool/run_oncvpsp_from_upf.sh Na.UPF
tool/run_oncvpsp_from_upf.sh Na.UPF -o reports/Na.out
tool/run_oncvpsp_from_upf.sh Na.UPF -o -
```

默认输出到输入文件旁：将 `.UPF` 后缀（不区分大小写）替换为 `.oncvpsp.stdout`；没有该后缀时追加 `.oncvpsp.stdout`。`-o PATH` 指定输出文件，`-o -` 将报告输出到 stdout。运行成功后才发布报告；指定文件时，在目标目录暂存后替换已有文件。摘要和诊断写入 stderr。

`--oncvpsp PATH` 可以指定可执行文件或安装目录：文件表示直接使用指定程序，UPF 类型推断仅作提示；目录表示根据 UPF 的相对论类型自动选择程序，未知类型或元数据冲突会报错。未指定时先使用非空的 `ONCVPSP_DIR`，再从 PATH 查找。编译器运行库、模块等环境由调用者准备。

默认在调用目录创建独立的 `.oncvpsp-work.XXXXXX/`，退出时清理，不使用 `/tmp`。`--keep-workdir DIR` 在新建的 DIR 中运行，并在成功或失败时保留完整现场；DIR 必须不存在，父目录必须已存在。

```bash
tool/run_oncvpsp_from_upf.sh Na.UPF --keep-workdir Na-run
```

工作目录包含提取的 `oncvpsp.in`、完整或不完整的 `oncvpsp.stdout`、`oncvpsp.stderr`。输入提取失败时可能只有不完整的输入文件。正式报告另行发布，保留目录中的报告副本不移走。此环境的 ONCVPSP 将常规报告、UPF 和 PSP8 数据写到 stdout；当生成输入的 `psfile` 为 `psml` 或 `both` 时，还会在工作目录生成 `_tmp_input` 和 `ONCVPSP.psml`。

## extract_oncv_corecharge.sh

从已有 ONCVPSP 报告提取芯电荷表，输出两列：半径 `r [bohr]` 和全电子芯密度 `rho_core [e/bohr^3]`。此步骤除去 ONCVPSP 数据中的 `4*pi` 因子，不运行生成器。

```bash
tool/extract_oncv_corecharge.sh Na.oncvpsp.stdout
tool/extract_oncv_corecharge.sh reports/Na.out -o Na.corecharge
tool/extract_oncv_corecharge.sh Na.oncvpsp.stdout -o -
```

文件输入默认将 `.oncvpsp.stdout` 后缀替换为 `.corecharge`；其他文件名直接追加 `.corecharge`。无输入参数或输入为 `-` 时从 stdin 读取，此时必须显式指定 `-o PATH` 或 `-o -`。摘要、积分和警告写入 stderr。

`--tag auto|R|r` 选择数据块：

- `auto`（默认）：优先 `!R`；没有 `!R` 数据时回退到 `!r`，并警告。
- `R`：要求补丁输出的 `!R` 数据，不回退。
- `r`：读取 `!r` 绘图数据。其网格经过稀疏化，密度可能被裁剪，所得芯电荷积分可能偏低。

验证成功后才发布结果；损坏的 `!R` 数据不会触发自动回退。文件输出在目标目录暂存后替换；stdout 输出在调用目录暂存，不使用 `/tmp`。强制选择 `R` 或 `r` 时忽略另一数据块。`--source-upf PATH` 仅在表头记录来源，不读取 UPF 或改变数据。

两步可以通过管道连接，只保存最终芯电荷表：

```bash
set -o pipefail
tool/run_oncvpsp_from_upf.sh Na.UPF -o - |
  tool/extract_oncv_corecharge.sh --source-upf Na.UPF -o Na.corecharge
```

需要保留完整报告供检查或再次提取时，使用分步的文件输出。使用 `-o PATH` 可以在计算或验证失败时保护已有结果；shell 的 `> PATH` 会提前截断文件，不能提供同样的保护。
