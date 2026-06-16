# MiTun

KernelSU 模块，以 TUN 模式运行 [mihomo](https://github.com/MetaCubeX/mihomo) 或 [sing-box](https://github.com/SagerNet/sing-box)，对 Android 设备流量做透明代理。

## 环境要求

- KernelSU ≥ 0.7.0
- Android ≥ 8.0（API 26）
- mihomo ≥ 1.18.0，或 sing-box ≥ 0.9.0

## 安装

1. 在 KernelSU 管理器安装 `mitun-vX.Y.Z.zip`
2. 安装器会复制示例配置到 `/data/adb/mitun/config.yaml.example` 和 `/data/adb/mitun/config.json.example`
3. 编辑示例配置后复制为实际配置，并放置对应可执行内核：
   - mihomo: `/data/adb/mitun/mihomo` + `/data/adb/mitun/config.yaml`
   - sing-box: `/data/adb/mitun/sing-box` + `/data/adb/mitun/config.json`
4. `chmod 0755` 对应内核
5. 重启设备

> 安装器只复制 `.example` 示例文件，不会自动生成或覆盖实际配置。实际启动哪个内核由可执行文件和实际配置文件是否同时存在决定；同时存在两组文件时，模块优先启动 mihomo。
>
> 请保证配置文件中的 Web 控制端口、Web UI 路径和 TUN 接口名和示例配置一致，否则将影响模块运行。

## 控制

通过 KernelSU 管理器的 **Action** 按钮切换启停：
- 进程未运行时 → 启动
- 进程正在运行时 → 停止

## Web 控制台

```
http://127.0.0.1:9090/ui
```

mihomo 示例配置已启用该入口，密码即 `config.yaml` 的 `secret`。sing-box 需在 `config.json` 中自行配置兼容控制接口和面板。

## 文件布局

```
/data/adb/modules/mitun/        # 模块本体（KernelSU 管理）
├── service.sh                  # late_start 入口
├── boot-completed.sh           # 启动健康检查
├── action.sh                   # Action 按钮
├── common_functions.sh         # 共享函数库
└── uninstall.sh

/data/adb/mitun/                # 用户数据（保留数据，不会在升级/卸载时移除）
├── mihomo                      # mihomo 二进制（自备）
├── config.yaml                 # mihomo 配置（自备）
├── config.yaml.example         # mihomo 示例配置
├── sing-box                    # sing-box 二进制（自备）
├── config.json                 # sing-box 配置（自备）
├── config.json.example         # sing-box 示例配置
└── run/
    ├── mitun.pid
    ├── mihomo.log              # mihomo 进程日志
    ├── sing-box.log            # sing-box 进程日志
    └── mitun.log               # 模块运维日志
```

## 故障排查

```bash
# 日志
tail /data/adb/mitun/run/mihomo.log
tail /data/adb/mitun/run/sing-box.log
tail /data/adb/mitun/run/mitun.log

# mihomo 示例配置的 TUN 接口
ip link show mihomo

# SELinux 拒绝
dmesg | grep avc
```

如果日志出现 `avc: denied`，按拒绝项补充 `sepolicy.rule`；不要直接套用其他模块的大范围规则。

## 卸载

通过 KernelSU 管理器卸载。用户配置与二进制默认保留，彻底清除：

```bash
rm -rf /data/adb/mitun
```

## 许可证

[GPL-3.0](LICENSE)
