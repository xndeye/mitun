# MiTun

KernelSU 模块，以 TUN 模式运行 [Mihomo](https://github.com/MetaCubeX/mihomo)（clash-meta），对 Android 设备上的所有 TCP/UDP 流量进行透明代理。

## 环境要求

| 项目 | 要求 |
|------|------|
| KernelSU | ≥ 0.7.0 |
| Android | ≥ 8.0（API 26） |
| 架构 | `arm64` |
| 内核 TUN | `/dev/net/tun` 可用 |
| Mihomo | ≥ 1.18.0 |

## 安装

1. 从 [Releases](../../releases) 页面下载最新的 `mitun-vX.Y.Z.zip`
2. 打开 KernelSU 管理器，选择本地安装，选中下载的 zip 文件
3. 重启设备，模块将在启动完成后自动运行

> 首次安装会在 `/data/adb/mitun/config.yaml` 生成示例配置文件，**重启前请先完成配置**。

## 配置

编辑配置文件：

```bash
vi /data/adb/mitun/config.yaml
```

1. 填写 `proxy-providers` 中的订阅链接
2. 按需修改 `secret` 密码

完整配置示例参见 [`files/config.yaml.example`](files/config.yaml.example)，其中分流规则集来自 [xndeye/rule-merger](https://github.com/xndeye/rule-merger)，可按需替换为其他规则集。

**配置完成后验证语法并启动：**

```bash
sh /data/adb/mitun/mitun_ctl.sh validate
sh /data/adb/mitun/mitun_ctl.sh start
```

## 控制命令

在 KernelSU 管理器中点击模块的 **Action 按钮** 可快速切换启停状态。

也可通过 `mitun_ctl.sh` 进行精细控制：

```bash
CTL="sh /data/adb/mitun/mitun_ctl.sh"

$CTL start     # 启动 MiTun
$CTL stop      # 停止 MiTun
$CTL restart   # 重启（stop → 等待 2s → start）
$CTL status    # 查看运行状态、TUN 接口及路由
$CTL log       # 查看最近 50 行日志
$CTL reload    # 热重载配置（进程不重启）
$CTL validate  # 验证 config.yaml 语法
```

## Web 控制台

模块内置 [zashboard](https://github.com/Zephyruso/zashboard)，安装后可通过浏览器访问：

```
http://127.0.0.1:9090/ui
```

密码为 `config.yaml` 中 `secret` 字段的值。

## 文件布局

```
/data/adb/modules/mitun/        # 模块文件（由 KernelSU 管理）
├── service.sh                  # 开机自启入口
├── boot-completed.sh           # 启动完成后健康检查
├── action.sh                   # Action 按钮处理脚本
├── common_functions.sh         # 核心工具函数库
└── uninstall.sh                # 卸载清理脚本

/data/adb/mitun/                # 用户数据（升级时保留）
├── mihomo                      # Mihomo 可执行文件
├── config.yaml                 # 主配置文件（用户编辑）
├── mitun_ctl.sh                # 控制脚本
├── ui/                         # Web 控制台静态文件
├── GeoIP.dat / GeoSite.dat / geoip.metadb
└── run/
    ├── mihomo.pid              # 进程 PID
    └── mihomo.log              # 运行日志
```

## 工作原理

Mihomo 创建名为 `mihomo` 的虚拟 TUN 接口，所有出站流量经由该接口进入 Mihomo 进程，再按规则转发至代理节点或直连。`auto-route` 和 `auto-redirect` 选项自动管理路由表，DNS 请求通过 `dns-hijack: any:53` 拦截，以 fake-ip 模式在内部解析，防止 DNS 泄漏。

```
应用流量 → TUN 接口（mihomo） → Mihomo 进程 → 代理 / DIRECT
```

**TUN 协议栈选项**

| 协议栈 | TCP | UDP | 说明 |
|--------|-----|-----|------|
| `system` | 内核态 | 内核态 | 性能最佳 |
| `gvisor` | 用户态 | 用户态 | 兼容性最佳 |
| `mixed` | 内核态 | 用户态 | **Android 推荐** |
| `lwip` | 用户态 | 用户态 | 特殊场景 |

**关键路径速查**

| 项目 | 路径 |
|------|------|
| 配置文件 | `/data/adb/mitun/config.yaml` |
| 运行日志 | `/data/adb/mitun/run/mihomo.log` |
| PID 文件 | `/data/adb/mitun/run/mihomo.pid` |
| 控制脚本 | `/data/adb/mitun/mitun_ctl.sh` |
| TUN 接口 | `mihomo` |
| API 端点 | `127.0.0.1:9090` |

## 故障排查

**MiTun 无法启动**

```bash
sh /data/adb/mitun/mitun_ctl.sh validate
cat /data/adb/mitun/run/mihomo.log
```

**流量未被代理 — 检查 TUN 接口和路由**

```bash
ip link show mihomo
ip rule show | grep 9000
```

**`/dev/net/tun` 不存在** — `service.sh` 会在启动时自动创建。若问题持续：

```bash
mkdir -p /dev/net && mknod /dev/net/tun c 10 200 && chmod 666 /dev/net/tun
```

**SELinux 拒绝访问**

```bash
dmesg | grep avc | grep mihomo
```

## 卸载

通过 KernelSU 管理器卸载，或手动执行：

```bash
sh /data/adb/modules/mitun/uninstall.sh
```

卸载后用户配置文件 `/data/adb/mitun/config.yaml` 默认保留。如需彻底清除：

```bash
rm -rf /data/adb/mitun
```

## 许可证

[GPL-3.0](LICENSE)
