# annibale-kernel (BakaSU + features)

针对 **Redmi K90 / POCO F8 Pro（codename `annibale`，Qualcomm sun / SM8750）** 的
自定义内核仓库：以小米官方开源内核 `MiCode/Xiaomi_Kernel_OpenSource@annibale-w-oss`
为基线，按阶段加入：

- 近期安全补丁（ACK `android15-6.6-2026-10` 合并）
- BakaSU（内置 KernelSU + SUSFS）
- Baseband-guard（BBG 防格机）
- Droidspaces（含 SYSVIPC/IPC_NS kABI 补丁）
- NTSync
- NoMount
- ZRAM 增强（LZ4HC/LZ4K，内置）
- 网络增强（BBRv3 / IPSet / CAKE / CIFS / TTL）

当前方案为 **2A**：只替换 `boot` 分区里的 vmlinux，保留原厂 `vendor_dlkm/system_dlkm`
模块；因此 **KMI/ABI 必须保持兼容**，任何会改变导出符号 CRC / 结构体布局的补丁都要
特别小心（脚本里已做提示）。

---

## 构建环境

- GitHub Actions `ubuntu-24.04`（工作流已自带清盘、依赖安装）
- 或者本机 Ubuntu 22.04/24.04：≥16 GB RAM，≥150 GB 可用磁盘

## 里程碑（必须按顺序跑）

| milestone | 内容 | 目的 |
|---|---|---|
| `baseline` | 原样构建，不应用任何特性 | 先确认这棵 vendor 树能编译、并验证 2A 能开机 |
| `bakasu` | BakaSU + SUSFS 配置 | 验证内置 KSU 不影响启动 |
| `full` | 全部特性（BBG/Droidspaces/NTSync/NoMount/ZRAM/网络） | 逐项验证 |
| `security`（后续） | 合并 ACK 6.6.143 安全补丁 | 补漏洞，风险最高，最后做 |

每条都先 `fastboot boot boot.img` 临时启动验证，**不要直接 flash**。

## 使用方法

1. 创建 GitHub 仓库（建议 public，便于我通过 API 读取 Actions 日志）：
   ```bash
   cd annibale-kernel
   git init -b main
   git add -A && git commit -m "init: annibale kernel build pipeline"
   gh repo create <你的账号>/annibale-kernel --public --source=. --push
   ```
2. 在 Actions 里手动触发 `build-annibale`，第一次先选 `baseline`。
3. 下载 artifact：`boot.img`（96 MiB 分区，含 AVB footer）、`Image`、构建日志。
4. 测试：
   ```text
   fastboot boot boot.img        # 临时启动，不写分区
   # 确认能开机后再：
   fastboot flash boot boot.img
   ```
   恢复原厂：`fastboot flash boot <原厂boot.img>`（本仓库不包含原厂镜像，请自备）。

## 已知风险 / 注意事项

- **这棵源码的 Makefile 是 6.6.57**，而你手机 stock vmlinux 是 `6.6.118-android15-8-…-4k`；
  两者同为 android15-6.6 KMI，理论上厂商模块可加载，但必须实测（baseline 里程碑）。
- 如果 baseline 就卡 logo：说明 2A 不可行，需要改成“kernel+modules 一起重编并刷 vendor_dlkm”
  或回到 GKI 路线（你现有的 `GKI_KernelSU_SUSFS` workflow）。
- ZRAM / NTSync 在小米树里是 `*.ko` 模块；2A 模式下脚本会把它们改成 built-in（=y）并
  从 `annibale.bzl` 的模块清单里移除，避免“模块缺失”构建失败。ZRAM 内置后原厂
  `vendor_dlkm` 里的 `zram.ko` 可能加载失败，需要观察日志。
- `TARGET` 名目前由工作流自动尝试多个候选；第一次运行请把“诊断日志”发给我，我再锁定
  正确的 Kleaf target。
- 每次构建约 40–90 分钟，Actions 单 job 上限 6 小时。

## 维护方式

GitHub 仓库创建并推送后，把仓库地址发我；公开仓库我可以直接读取 Actions 运行日志/产物
元数据。此后每次构建失败，把 run 链接发我，我会基于日志修改本仓库文件，你再
`git pull && git commit && git push`（或直接使用我给出的 patch）。
