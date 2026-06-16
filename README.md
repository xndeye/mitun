# MiTun

KernelSU 模块，以 TUN 模式运行 [Mihomo](https://github.com/MetaCubeX/mihomo)，对 Android 设备的全部 TCP/UDP 流量做透明代理。

## 环境要求

- KernelSU ≥ 0.7.0
- Android ≥ 8.0（API 26）
- Mihomo ≥ 1.18.0

## 安装

1. 在 KernelSU 管理器安装 `mitun-vX.Y.Z.zip`
2. 将可执行的 mihomo 放置于 `/data/adb/mitun/mihomo`，`chmod 0755`
3. 编辑 `/data/adb/mitun/config.yaml` 填入订阅并修改 `secret`
4. 重启设备

> **以下字段请勿修改**，否则会破坏模块内部集成：
>
> - `external-controller: 127.0.0.1:9090` — Web 控制台跳转依赖该端口
> - `external-ui: ui` — Web 控制台静态资源路径
> - `tun.device: mihomo` — 模块按此接口名定位 TUN；如需更改需同步改
>   `common_functions.sh` 中的 `TUN_DEVICE`

## 控制

通过 KernelSU 管理器的 **Action** 按钮切换启停：
- 进程未运行时 → 启动
- 进程正在运行时 → 停止

## Web 控制台

```
http://127.0.0.1:9090/ui
```

密码即 `config.yaml` 的 `secret`。

## 文件布局

```
/data/adb/modules/mitun/        # 模块本体（KernelSU 管理）
├── service.sh                  # late_start 入口
├── boot-completed.sh           # 启动健康检查
├── action.sh                   # Action 按钮
├── common_functions.sh         # 共享函数库
└── uninstall.sh

/data/adb/mitun/                # 用户数据（升级保留）
├── mihomo                      # 二进制（自备）
├── config.yaml                 # 主配置
└── run/
    ├── mihomo.pid
    ├── mihomo.log              # mihomo 进程日志
    └── mitun.log               # 模块运维日志
```

## 故障排查

```bash
# 日志
tail /data/adb/mitun/run/mihomo.log
tail /data/adb/mitun/run/mitun.log

# TUN 接口
ip link show mihomo

# SELinux 拒绝
dmesg | grep avc | grep mihomo
```

如果日志出现 `avc: denied`，按拒绝项补充 `sepolicy.rule`；不要直接套用其他模块的大范围规则。

## 卸载

通过 KernelSU 管理器卸载。用户配置与二进制默认保留，彻底清除：

```bash
rm -rf /data/adb/mitun
```

## 许可证

[GPL-3.0](LICENSE)
