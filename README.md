# ssh-status

一个用于 SSH 交互式登录的只读状态面板。目标是让管理员进入 VPS 后，不额外输入命令就能看到机器的核心资源、磁盘和 Docker 健康状态。

> 设计原则：不修改网络队列、iptables、Docker 容器或系统配置；不请求公网 API；非交互式 SSH、`scp`、`rsync` 和 `ssh host command` 均不输出任何内容。

## 目标界面

```text
╭─ server.example ─ Ubuntu 24.04 ─ 2026-07-10 14:30 ───────────────────╮
│ 核心信息  CPU  : AMD EPYC 7B12 (4C/8T)     IP   : 10.0.0.12          │
│           Uptime: 18d 04h 12m                                            │
├──────────────────────────────────────────────────────────────────────┤
│ 资源使用  Load : 0.21 / 0.17 / 0.14     Processes : 142    Users : 1 │
│           Memory: 2.3 GiB / 7.7 GiB (30%)  Swap: 0 B / 2.0 GiB (0%)  │
├──────────────────────────────────────────────────────────────────────┤
│ 磁盘 /       18G / 80G  (23%)  [█████░░░░░░░░░░░░░░░]                 │
│      /data   220G / 500G (44%)  [██████████░░░░░░░░░]                 │
├──────────────────────────────────────────────────────────────────────┤
│ Docker     6 containers: 5 running, 1 stopped                         │
│            ! unhealthy: api (unhealthy)                                │
├──────────────────────────────────────────────────────────────────────┤
│ 系统健康  ! systemd: nginx.service (failed)    ! 重启：需要            │
╰──────────────────────────────────────────────────────────────────────╯
```

没有安装 Docker 时，整段 Docker 信息不显示。当前用户无法读取 Docker Socket 时，脚本会尝试 `sudo -n docker ps`；该命令只接受已配置的无密码 sudo，绝不会提示输入密码或中断登录。两种方式都失败时显示“无法读取 Docker 状态（权限或服务异常）”。

## 展示范围

| 区块 | 展示内容 | 数据来源 |
|---|---|---|
| 核心信息 | CPU 型号、主 IPv4、运行时间 | `/proc/cpuinfo`、`ip route`、`/proc/uptime` |
| 资源使用 | 1/5/15 分钟负载、内存、Swap、进程数、在线用户 | `/proc/loadavg`、`free`、`ps`、`who` |
| 磁盘 | 各真实挂载点的已用/总量/占比和进度条 | `df -P -x tmpfs -x devtmpfs` |
| Docker | 总数、运行数、停止数、不健康/重启/死亡容器名称 | `docker ps` |
| 系统健康 | systemd 失败服务、是否需要重启 | `systemctl --failed --no-legend`、`/var/run/reboot-required` |

“IP 地址”默认为主网卡 IPv4，而非依赖第三方服务查询公网 IP；这样登录没有网络等待和隐私泄露。需要公网 IP 时，后续可单独增加明确启用的 `public_ip` 选项。

## 运行模式

### 登录横幅（默认）

执行一次并退出；不做网速采样，因此不会因等待采样而拖慢 SSH 登录。

### 刷新模式（可选）

```bash
ssh-status --watch
ssh-status --watch 2  # 每 2 秒刷新
```

刷新模式清屏更新 CPU 负载、内存、磁盘、Docker 和系统健康状态。横幅模式只应放入 `/etc/profile.d/`，绝不放入 `.bashrc` 的无条件分支，以免干扰非登录 shell。

## 系统健康项与后续可选信息

首版加入下列两个“需要处理时才重要”的状态；正常时只显示简短摘要，异常时红色列出详情。

| 信息 | 建议 | 原因与实现 |
|---|---|---|
| systemd 失败服务 | 首版启用 | `systemctl --failed --no-legend`；有失败服务时红色列出，正常时显示 `systemd: OK`。`systemctl` 不可用时显示 `N/A`。 |
| 重启提示 | 首版启用 | Debian/Ubuntu 检查 `/var/run/reboot-required`；存在则红色显示“需要重启”，不存在则显示 `Reboot: no`。其他发行版安全显示 `N/A`。 |
| inode 使用率 | 后续可选 | 容量充足但 inode 耗尽同样会导致“磁盘写不进去”；用 `df -Pi`，仅在达到 80% 时显示。 |
| 可更新软件包数 | 可选 | 对安全运维有用，但包管理器查询可能变慢；应由定时任务写缓存，登录只读缓存。 |
| 最近一次成功 SSH 登录 | 可选 | 可帮助发现异常登录；只显示当前用户自己的记录，避免向其他用户泄露登录活动。 |
| 公网 IPv4 | 可选 | 仅在配置明确启用且设置短超时时查询，默认关闭，避免引入第三方网络依赖。 |

这两个状态比瞬时网速更直接关联“这台机器是否需要处理”。

## 主题与终端兼容性

内置主题：

| 名称 | 风格 | 用途 |
|---|---|---|
| `retro-arcade` | 霓虹青标题、粉色正文、紫色边框、黄/洋红告警 | 默认，使用用户提供的 Retro Arcade 真彩色板 |
| `ocean` | 青蓝标题、灰蓝边框、柔和绿/琥珀告警 | 适合深色终端 |
| `forest` | 柔和绿色标题、深灰边框、琥珀告警 | 偏传统 Unix 风格 |
| `mono` | 无 ANSI 颜色 | 日志、弱终端、截图 |

颜色遵从以下优先级：`--theme` > `SSH_STATUS_THEME` > 配置文件 > `retro-arcade`。`retro-arcade` 使用 `#FF00FF`、`#00FFFF`、`#FFFF00`、`#FF69B4` 和 `#7B68EE` 真彩色，并为正文与全部框线着色。若 `NO_COLOR` 已设置、终端不是 TTY 或 `TERM=dumb`，自动退化为 `mono`。进度条使用纯 Unicode 方块，并提供 ASCII 后备模式。面板默认最大宽度为 70 列，可通过配置文件的 `max_width` 或环境变量 `SSH_STATUS_MAX_WIDTH` 调整；窄终端仍会自动收缩。

告警颜色阈值：磁盘或内存使用率 80% 为黄，90% 为洋红；Docker 的 `unhealthy`、`dead`、`restarting` 为洋红，`exited` 为黄。

## Docker 健康判定

Docker 区块为只读查询，异常定义如下：

- `health=unhealthy`：红色，列出容器名；
- `status=dead` 或 `restarting`：红色；
- `status=exited`：黄色，作为停止容器计数并列出名称；
- `running` 且健康状态为 `healthy` 或未配置健康检查：正常。

脚本不自动执行 `docker restart`、`docker prune` 或任何修复动作。注意：加入 `docker` 用户组或允许无密码运行 Docker 通常等价于授予主机 root 级能力；`sudo` 后备查询仅适用于管理员已经明确接受该权限模型的主机。

## 计划文件结构

```text
ssh-status/
├── README.md                       # 本设计与运维说明
├── src/
│   ├── ssh-status                  # Bash 主程序：采集、渲染、刷新模式
│   └── ssh-status-login.sh         # /etc/profile.d 的交互式登录守卫
├── config/
│   └── config.example              # theme、disk 排除项、Docker 展示开关
├── install.sh                      # 仅复制文件，不安装包、不下载二进制
└── tests/
    └── smoke.sh                    # 以 fixture 验证渲染与降级逻辑
```

主程序使用 Bash 4+、`awk`、`sed`、`df`、`ip`、`free`、`ps`、`who` 等常见 Linux 工具；Docker 为可选依赖。不会引入 YAML 解析器、Python、Go 二进制或外部下载器。

## 安装、测试与卸载

在 Debian、Ubuntu 等使用 Bash 4+ 的 Linux VPS 上执行：

```bash
git clone https://github.com/telly3e/ssh-status.git
cd ssh-status
sudo bash install.sh
```

安装器只复制本仓库文件，不安装软件包、不访问网络。默认安装位置如下：

| 文件 | 安装位置 |
|---|---|
| 主程序 | `/usr/local/bin/ssh-status` |
| 配置文件 | `/etc/ssh-status.conf` |
| Bash 登录守卫 | `/etc/profile.d/20-ssh-status.sh` |
| zsh 登录守卫 | `/etc/zsh/zprofile.d/20-ssh-status.zsh`（目录存在时） |

安装后可以先手动运行并执行 smoke test：

```bash
ssh-status
bash tests/smoke.sh
```

再新建一个 SSH 会话检查登录横幅，并确认远程单命令没有额外输出：

```bash
ssh user@host
ssh user@host uptime
```

配置可编辑 `/etc/ssh-status.conf`；已有配置在重复安装和卸载时都会保留。卸载程序和登录守卫：

```bash
cd ssh-status
sudo bash install.sh --uninstall
```

## SSH 集成方式

安装器将主程序复制到 `/usr/local/bin/ssh-status`，再写入一个小的 `/etc/profile.d/20-ssh-status.sh`：

```bash
# 只在交互式、分配 TTY 的登录会话显示；scp/rsync/远程单命令不受影响。
case $- in
  *i*) [ -n "${SSH_TTY:-}" ] && command -v ssh-status >/dev/null && ssh-status ;;
esac
```

对于 zsh 登录 shell，安装器额外写入受同样条件保护的 `/etc/zsh/zprofile.d/20-ssh-status.zsh`（仅在该目录存在时）。

## 开发顺序

1. 先完成无 Docker 的单次渲染：核心、资源、磁盘进度条与主题。
2. 加入 Docker 只读检测和权限降级。
3. 加入 systemd 失败服务和重启提示的系统健康区块。
4. 实现 `--watch` 刷新模式、profile 守卫、配置文件与卸载路径。
5. 在 Debian/Ubuntu、Docker 存在/不存在、无 Docker 权限、无颜色终端下跑 smoke test。

## 验收标准

- 交互式 SSH 登录不进行网络采样，能快速完成首屏展示；
- `ssh host uptime`、`scp`、`rsync` 的标准输出完全不变；
- Docker 不存在或无权限时退出码仍为 0；
- 不产生网络、文件系统或 Docker 状态变更；
- 磁盘、内存、Docker 异常在窄终端中可读，不因长容器名破坏布局。
