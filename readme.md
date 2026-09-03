<div align="center">

# GKI KernelSU SUSFS
### 专为ReSukiSU打造的自动构建仓库

**自动化构建 GKI 内核 | 集成 ReSukiSU + SUSFS**

[![Release](https://img.shields.io/github/v/release/coolzyd9107/GKI_KernelSU_SUSFS?label=Release&style=flat-square&logo=github&logoColor=white&color=2ea44f)](https://github.com/ReSukiSU-GKI/GKI_KernelSU_SUSFS/releases)
[![Telegram](https://img.shields.io/static/v1?label=Telegram&message=Channel&color=0088cc)](https://t.me/ReSukiSUKernelBuilds)
[![ReSukiSU](https://img.shields.io/badge/ReSukiSU-Supported-5AA300?style=flat-square)](https://kernelsu.org/)
[![SUSFS](https://img.shields.io/badge/SUSFS-Integrated-E67E22?style=flat-square)](https://gitlab.com/simonpunk/susfs4ksu)

---

</div>

## ⚠️ 仓库须知

① 本仓库分叉自 [zzh20188/GKI_KernelSU_SUSFS](https://github.com/zzh20188/GKI_KernelSU_SUSFS/) 本人只进行了部分修改与问题修复，请各位使用者优先考虑分叉原始仓库。

② 本仓库仅支持构建包含ReSukiSU的内核，对其它KernelSU分支的内核构建支持现已彻底移除，如需构建包含其他KernelSU分支的内核，请分叉上游仓库 [zzh20188/GKI_KernelSU_SUSFS](https://github.com/zzh20188/GKI_KernelSU_SUSFS/) 然后自行构建。

## 💰 特别鸣谢

[coolzyd9107](https://github.com/coolzyd9107)：仓库的创建者和所有者，但他是一个大fèiwù，很多东西都不会。

[zzh20188](https://github.com/zzh20188)：他是本仓库的上游仓库作者。

[zhuzhuzihan](https://github.com/zhuzhuzihan)：协助进行了大量修复和修改，同时为我们的Telegram Bot提供服务器(仓库所有者真的太穷了，租不起)，我们的Telegram Bot的主要开发者。

[TanakaLun](https://github.com/TanakaLun)：协助进行了大量修复和修改。

[YC酱luyancib](https://github.com/luyanci): 协助开发Telegram Bot，提供部分构建工作流程修复思路和Bot开发思路。

[AlexLiuDev233](https://github.com/AlexLiuDev233): 协助修复构建工作流程存在的问题。

[cctv18](https://github.com/cctv18): 协助修复构建工作流程存在的问题，为添加6.12内核构建支持提供部分思路，为修复一些SUSFS导致的问题提供思路。

注:带*号的username表示该协作者的github账户处于不可见状态

---

## ⚠️ 重要更新日志

> **注意：** 目前不支持一加 ColorOS 14、15，刷入后可能需要清除数据开机。

> **ReSukiSU：ReSukiSU更新比SukiSU勤快，SukiSU报错就试试ReSukiSU**
>
> **默认变体已切换为 ReSukiSU**

> **Android 16：已支持 Android 16 - 6.12 内核版本**
>
> **自本仓库的提交#c17aae5起我们已彻底移除对除ReSukiSU以外的KernelSU变体的内核构建支持，如果你出于某种原因更喜欢使用其他KernelSU变体的管理器，你完全不必担心，我们启用了muti-manager (内核中的KernelSU驱动程序仍是ReSukiSU，但支持使用其它大部分KernelSU变体的管理器进行管理，例如KowSU和SukiSU-Ultra的管理器) ，这样你就可以直接使用其他KernelSU变体的管理器，但请务必记住，如果你要反馈问题，请使用ReSukiSU管理器提交日志信息**

> **rekernel功能（测试）：已支持 rekernel 功能（目前处于测试阶段）**

> **全部GKI编译工作流已从在工作流文件中硬编码GKI版本号迁移至json读取以方便后续同步GKI版本号，避免发布release时缺少最新或近期更新发布的GKI版本**

## 🧪 Bypass 内核构建（可选）

手动触发构建时可启用 `build_bypass`。该选项默认关闭；启用后每个目标会连续构建普通内核和 Bypass 内核，并将两份 `Image` 放入同一个 AnyKernel3 压缩包：

- 普通模式使用 `Image`，作为默认推荐选项。
- Bypass 模式使用 `Bypass-Image`，仅用于内核模块版本兼容性问题，不用于绕过 root 检测。
- 刷入时按提示使用音量键选择模式：音量减选择普通模式，音量加选择 Bypass 模式。

启用该选项会进行第二次完整编译，因此构建时间和磁盘占用会增加。只有在普通内核因模块兼容性问题无法启动时才应尝试 Bypass 模式。

---

## 🧪 Droidspaces 容器支持（实验性）

> **实验性功能：** 不保证所有 GKI 版本均能成功构建或启动，刷入前请务必备份 Boot 镜像。
>
> **TIPS：** 工作流使用的是 [Droidspaces](https://github.com/ravindu644/Droidspaces-OSS) 的 [官方补丁](https://github.com/ravindu644/Droidspaces-OSS/tree/main/Documentation/resources/kernel-patches/GKI) ，如有更好的补丁可以提个issues，此外由于存在三个补丁，或许需要反复试验以确保其中一个适配你的机型，请根据他人或实际经验来选择。

[Droidspaces](https://github.com/ravindu644/Droidspaces-OSS) 是一个轻量级的 Linux 容器工具，可以在 Android 上运行完整的 Linux 环境（支持 systemd、OpenRC 等），用于搭建开发环境、运行服务器等场景。

**支持范围：** 5.10 / 5.15 / 6.1 / 6.6 / 6.12

**使用方式：** 在手动触发构建时，选择 `Droidspaces 容器支持` 选项：

| 选项 | 说明 |
|:---:|:---|
| `off` | 关闭（默认） |
| `678` | 使用 6_7_8 槽位补丁（推荐） |
| `123` | 使用 1_2_3 槽位补丁（备用） |
| `345` | 使用 3_4_5 槽位补丁（备用） |

> **提示：** 6.12 内核仅有一个补丁，选择任意非关闭选项即可。

**如果构建失败或刷入后 bootloop：** 可尝试切换到其他槽位补丁（如 678 → 123 或 345），不同内核子版本可能适用不同的补丁。

---

## 🧪 伪装 `/proc/config.gz`（Stock Config）

这是一个进阶技巧，不需要在工作流里手动开关。  
构建时会自动检测 `config/stock_defconfig` 是否存在：存在则应用，不存在则跳过。

使用方法：
1. 确保设备当前是官方 ROM + 官方内核。
2. 获取设备上的 `/proc/config.gz`（可在手机端或电脑端操作）。
3. 解压后重命名为 `stock_defconfig`，上传到仓库 [`config/`](config/) 目录并提交（可直接在手机端完成）。

构建流程会自动：
- 复制到内核源码：`$KERNEL_ROOT/common/arch/arm64/configs/stock_defconfig`
- 在 `$KERNEL_ROOT/common/kernel/Makefile` 中将 `$(obj)/config_data` 规则从 `$(KCONFIG_CONFIG)` 切换为 `arch/arm64/configs/stock_defconfig`
- 使编译产物中的 `/proc/config.gz` 更贴近你的官方内核配置

---

<div align="center">

**更多内容持续更新中...**

⭐ 如果这个项目对你有帮助，请点个 Star 支持一下！

⭐ 新预构建发布通知/重大变更通知请关注我们的[Telegram频道](https://t.me/ReSukiSUKernelBuilds)

</div>
