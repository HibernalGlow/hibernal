# Hibernal

<p align="center">
  <img src="assets/readme/hero.svg" width="100%" alt="Hibernal — 让 macOS 按需进入深度休眠，默认快捷键 Control+Option+Command+反斜杠。标题下方是 App 自己 hibernate.log 的真实片段：hibernate start、hibernatemode 25、Sleeping now...、wake restore。">
</p>

<p align="center">
  <a href="README.md">English</a> &middot; 简体中文
</p>

MacBook 不会因为你希望它休眠就休眠。合盖得到的是睡眠，久置不动得到的是 standby。Hibernal 补上缺失的那扇门：把内存镜像写入磁盘并真正断电，一次按键完成。

## 一句话版本

- **`hibernatemode 25` + `pmset sleepnow`** — 内存镜像落盘、内存断电，而不是让机器在包里慢慢耗电。
- **一次按键，或菜单栏一次点击。** 默认快捷键 `Control + Option + Command + \`，可在设置里改。
- **合盖行为不变。** 可选在唤醒后恢复 `hibernatemode 3`，铰链继续干它一直干的事。
- **只输一次密码。** 干活的是特权助手；只有助手本身变了才会再问。
- **不猜结果。** 每次休眠都用内核计数器核对，没睡成就在日志里写没睡成。

## 真的休眠了的证据

下面这段是 Apple Silicon Mac（M4）上 `~/Library/Logs/Hibernal/hibernate.log` 的原样内容：

```text
=== Fri Oct  2 03:37:32 CST 2026 hibernate start ===
Now drawing from 'AC Power'
 -InternalBattery-0 (id=7471203)	100%; charged; 0:00 remaining present: true
=== Fri Oct  2 03:37:32 CST 2026 ejecting external drives ===
Disk /dev/disk4 ejected
Disk /dev/disk5 ejected
 hibernatemode        25
 hibernatemode        25
Sleeping now...
=== Fri Oct  2 03:48:04 CST 2026 wake restore ===
=== Fri Oct  2 03:48:06 CST 2026 hibernate end ===
```

这段日志能自证：只有脚本运行期间 `kern.hibernatecount` 真的变了，才会打出 `wake restore`；否则脚本提前退出并写下 `sleepnow did not hibernate`。机器睡了十分钟出头，回来还是原来那个会话。在你自己的 Mac 上，两条命令能说明同一件事：

```bash
pmset -g log | grep -c "Wake from Hibernate"   # 真正从休眠里醒过来过几次
sysctl -n kern.hibernatecount                   # Hibernal 前后比对的那个计数器
```

## 一次按键到底跑了什么

<p align="center">
  <img src="assets/readme/mechanism.svg" width="100%" alt="六个有序步骤：菜单栏或快捷键触发；读 pmset -g assertions，必要时用倒计时等过冷却；SIGSTOP 卡住睡眠的进程、停掉 Time Machine、按需推出磁盘；设置 hibernatemode 25 并关闭 standby、Power Nap、网络唤醒；pmset sleepnow 后用 kern.hibernatecount 验证；唤醒后恢复 hibernatemode 3。">
</p>

1. **触发** — 全局快捷键，或菜单栏里的**立即休眠**。后一次请求会让前一次待执行的作废。
2. **看冷却脸色** — 先读 `pmset -g assertions`。如果 `hibernate user wake`、`acwakelinger` 或 `darkwakelinger` 在册，会弹一个小面板倒计时，而不是硬睡进一个会拒绝的系统；三条上限分别是 125 秒、45 秒、10 秒。
3. **清场** — 用 `SIGSTOP` 暂停卡住睡眠的进程（`AMPDeviceDiscoveryAgent`、`AMPSystemPlayerAgent`，以及在跑的 `grok-macos-aarch64`），并中止正在进行的 Time Machine 备份。外接物理磁盘只有你打开开关才推出；网络卷一律不碰。
4. **上膛** — 三个电源档位都设 `hibernatemode 25`，外加 `standby 0`、`autopoweroff 0`、`powernap 0`、`womp 0`。
5. **睡，并且自证** — `pmset sleepnow` 之后再读一次 `kern.hibernatecount`。数值没动，`hibernatemode` 就故意留在 25，日志写 `sleepnow did not hibernate`，不会假装已经恢复过了。
6. **唤醒后恢复** — 「唤醒后恢复普通睡眠」开着时（默认开），`hibernatemode` 回到 `3`，`standby`、`autopoweroff`、`powernap`、`womp` 回到 `1`；被暂停的 Grok agent 收到 `SIGCONT`，`AirPlayXPCHelper` 被 kickstart，Finder 重新启动一次。

## 谁在跑，用什么权限

<p align="center">
  <img src="assets/readme/trust-boundary.svg" width="100%" alt="三跳：Hibernal.app 以你的身份运行并写出 hibernate.sh；经 XPC 交给以 root 运行、位于 /Library/PrivilegedHelperTools 的 com.hibernal.helper；由它调用 pmset 设置 hibernatemode 25 并 sleepnow。就绪与否是内嵌助手与已装助手的 SHA-256 比对。">
</p>

App 自己从不提权。它把脚本写到 `~/Library/Application Support/Hibernal/hibernate.sh`，再把路径交给 `com.hibernal.helper`，由后者以 root 一次性跑完。就绪判定是「App 内嵌的助手」与「磁盘上已安装的助手」之间的 SHA-256 比对 — 所以**升级 Hibernal 不会再次向你要密码**，只有助手真的变了才会重新弹。

如果助手缺失或拒绝执行，App 会退回到一次 `do shell script … with administrator privileges` 授权，仅覆盖这一次。设置窗口里直接写着状态：助手那一行是绿点，说明休眠不会再问你要任何东西；橙点则意味着下一次休眠会问。

## 安装

```bash
brew install --cask hibernalglow/tap/hibernal
```

或者从[最新版本页](https://github.com/HibernalGlow/hibernal/releases/latest)下载 `Hibernal-<version>.dmg`，挂载后把 **Hibernal** 拖进**应用程序**。

构建产物是**临时签名（ad-hoc）且未公证**的 — 这个项目没有 Developer ID。签名本身是有效的（`codesign --verify --deep --strict` 通过），所以 Finder 不会说 App 已损坏，但带隔离属性的下载仍需一次手动放行：**系统设置 → 隐私与安全性 → 仍要打开**。Homebrew 安装同样会打隔离标记，因此每次安装或升级后都要放行这一次。

然后：按下 `Control + Option + Command + \`，输一次密码装助手，机器就进入休眠。带刘海的 MacBook 上月亮图标可能被收进菜单栏 `•••` 溢出区 — 快捷键在两种情况下都照常生效。

手工把副本挪进「应用程序」？先**退出 App**，再把**登录时启动**关一次开一次 — 登录项记的是绝对路径，只有这个开关会把它重写。

## 设置

| 选项 | 默认 | 作用 |
|------|------|------|
| **启用休眠** | 开 | 快捷键与休眠动作的总开关 |
| **唤醒后恢复普通睡眠（hibernatemode 3）** | 开 | 快捷键休眠之后把机器恢复成标准合盖行为 |
| **休眠前推出外接磁盘** | 关 | 安全推出 USB、雷雳和 SD 卡卷；网络驱动器不受影响 |
| **接电源时保持唤醒** | 关 | 插电时 `pmset -c sleep 0`；关掉会恢复 10 分钟的电源睡眠计时 |
| **登录时启动** | 开 | 登录时隐藏到菜单栏启动 |
| **键盘快捷键** | `⌃⌥⌘ \` | 用「更改快捷键…」重绑 |

**在终端中查看 pmset** 会打开一个生成的 `pmset-check.command`，依次打印 `pmset -g`、`-g custom`、`-g assertions`，让你亲眼看到 App 读取和写入的状态。

窗口与服务控制：**Cmd+Q** 或红点只是隐藏设置窗口，菜单栏继续活着；**停止后台服务**关掉图标和快捷键；**重新启动 App** 恢复它们；**退出 App** 才是真的退出。

## 值得知道的边界

- **刚醒过来就想再睡一次是最脆弱的情形。** 在一台 M 系列 Mac 上实测：从休眠唤醒后，`powerd` 会持有 `hibernate user wake` 断言 **600 秒**，而 Hibernal 最多等 **125 秒**就会强行 `pmset sleepnow`。在这个窗口里，强行睡眠有时真的休眠、有时只是睡觉，所以倒计时不是保证。用 `pmset -g log` 看有没有 `Wake from Hibernate` 来判断你拿到的是哪种 — 如果没睡成，`hibernatemode` 仍留在 25，下次合盖就会休眠。
- **休眠后约十分钟自己醒过来，不是这个 App 干的。** 每次睡眠时 `powerd` 都会排一个对用户不可见的唤醒闹钟，约 590 秒后触发，注册方是 `AppleCredentialManagerDaemon`（`com.apple.alarm.user-invisible-com.apple.acmd.alarm`）。它在待触发时不出现在 `pmset -g sched` 里，`pmset schedule cancelall` 也删不掉，而不建议关掉 AppleCredentialManager — 那是系统级的凭证/TPM 守护进程。
- **刚登录时快捷键可能慢一拍。** 它在后台服务启动时注册，并在唤醒、解锁屏幕、App 转为活动这三种时机重新注册 — 所以解锁屏幕或打开一次设置窗口就是让它刷新的办法。

## 文件都在哪

| 路径 | 是什么 |
|------|--------|
| `~/Library/Logs/Hibernal/hibernate.log` | 每次休眠的完整过程，从 start 到 restore |
| `~/Library/Logs/Hibernal/power.log` | 电源保持唤醒的变更 |
| `~/Library/Application Support/Hibernal/` | `hibernate.sh`、`pmset-check.command`、`hibernate.lock` |
| `/Library/PrivilegedHelperTools/com.hibernal.helper` | 以 root 运行的助手（Bundle id `com.hibernal.app`，登录项 `com.hibernal.agent`） |
| `com.hibernal.settings` | 设置窗口背后的偏好域 |

内置英文与简体中文，跟随系统语言；`CFBundleLocalizations` 两个都列了，所以你也可以在系统设置里只给这个 App 钉定一种语言。

## 从源码构建

```bash
git clone https://github.com/HibernalGlow/hibernal.git
cd hibernal
./build-dmg.sh          # 只要 bundle 就跑 ./build-app.sh
```

需要 macOS 13.0+，以及提供 `swiftc` 和 `codesign` 的 Xcode 命令行工具。产物是 `dist/Hibernal.app` 和 `releases/Hibernal-<version>.dmg`（两者都在 gitignore 里；发布资产由 CI 产出）。

`build-app.sh` 会编译 `ARCHS` 里的每个架构（默认 `arm64 x86_64`），用 `lipo` 合成一个通用二进制，再由内向外签名 — 先签助手，再封 bundle — 如果 `codesign --verify --deep --strict` 不通过就让构建失败。设置 `SIGN_IDENTITY="Developer ID Application: …"` 可用真实证书签名。

推送 `v*` 标签会触发 `.github/workflows/release.yml`，它负责构建、校验、把 DMG 作为发布资产上传，并在任务摘要里打印 sha256 供 Homebrew cask 使用。

## 2.0.0 改名

*Hibernate Control* 更名为 **Hibernal**，bundle id（`com.hibernal.app`）、助手（`com.hibernal.helper`）、登录项（`com.hibernal.agent`）和偏好域一并更换。2.0.0 之前的副本会留下旧的助手和登录项，新版本可用后请清掉：

```bash
sudo launchctl bootout system/com.hibernatecontrol.helper
sudo rm /Library/LaunchDaemons/com.hibernatecontrol.helper.plist \
        /Library/PrivilegedHelperTools/com.hibernatecontrol.helper \
        ~/Library/LaunchAgents/com.hibernatecontrol.agent.plist
```

## 许可

个人工具项目，风险自负 — 休眠会影响电源状态和未保存的工作。
