# 全局热键失效（Option+Space / Option+`）

创建时间: 2026-05-27
分支: feature/focused-conversation-memory
状态: 已解决（缓解）— 监测 + 用户可见 Banner + 设置页诊断 + 一键重注册

## 症状

- 用户按 Option+Space、Option+\` 完全无响应（不开面板、不开快捷输入条）
- 历史上能用，"之前解决但目前又出现了"
- 菜单栏图标点击仍正常 → 说明 App 还活着，仅热键链路坏了

## 日志线索

`~/.opc-companion/logs/2026-05-27.log` 仅出现：
```
[DIAG] setupHotkey: START
[DIAG] Carbon hotkeys registered
[DIAG] setupHotkey: END
```
**完全没有** `[HOTKEY] Short press` / `[HOTKEY] Long press` / `[HOTKEY] Option+` 的痕迹 →
说明 `handleOptSpacePress` / `handleOptBacktickPress` 根本没被调用。

## 数据流路径

```
按键 (Option+Space)
  ↓
macOS 全局事件队列
  ↓
Carbon HotKey 系统派发 (kEventHotKeyPressed)
  ↓
CarbonHotkeyManager.installEventHandler 注册的 C callback
  ↓
GetEventParameter 取 hotKeyID
  ↓
DispatchQueue.main.async
  ↓
slots[hotKeyID.id] 查 slot
  ↓
slot.onPress() —— 闭包内调 [weak self] self?.handleOptSpacePress()
  ↓
AppDelegate.handleOptSpacePress 写日志 "[HOTKEY] Short press" 等
```

日志最后一行没出现 → 链路在 callback 入口或之前断掉。

## 当前 CarbonHotkeyManager 状态（target branch）

`feature/focused-conversation-memory` HEAD（495e8c6）上的 `CarbonHotkeyManager.swift` 是
**没有** NSLock 的原始版本（`ecfa47d` 的修复在 `auto-fix/daily-2026-05-18` 分支上，
**没合进** 当前主线）。

即：当前不存在锁重入死锁可能。但**也没有线程同步**，理论上 register 在 main、
callback 也 dispatch 到 main，读写都在 main 上没竞态——除非有其他线程调 register。
搜了一下没看到，register 只在 `setupHotkey()`（@MainActor）里调。

## 已排除的假设

- [x] CarbonHotkeyManager 死锁（NSLock 重入）—— 当前分支根本没 NSLock，不可能
- [x] `setupHotkey()` 没被调用 —— 日志显示 START / END 都打了
- [x] AppDelegate 不是单例被释放 —— `Self.shared = self` 在 init 里，且 `state` 引用还活着

## 当前主假设

**优先级 1：`RegisterEventHotKey` 返回非 noErr，但 register 没记日志。**
register 调用看似成功，实际可能因为以下原因失败：
- macOS 26 新策略要求声明 entitlement 或类似授权
- keyCode 49/50 + optionKey 已被系统/其他 App 占用（如 Spotlight 用 Cmd+Space，但
  Option+Space 不应冲突；不过 macOS 偶尔会把 Option+Space 给输入法切换）
- `GetApplicationEventTarget()` 在 LSUIElement App 启动早期返回的 target 不对

**优先级 2：`InstallEventHandler` 静默失败，eventHandler 根本没装上。**
当前实现在 init 时调 `installEventHandler()`，没检查 OSStatus 返回。如果失败，
后续 register 拿到的 hotKeyRef 没有 handler 监听 → 按键也不会触发回调。

**优先级 3：macOS 系统抢占了 Option+Space。**
macOS 系统输入源切换默认就是 Option+Space（中→英）/ Ctrl+Space。如果用户开了
"Select the previous input source: Option+Space"，Carbon 注册会被系统抢先吃掉事件。
这其实是**最有可能**的根因——非常常见。

## 修复策略

### 第 1 步：补全 OSStatus 诊断（不改逻辑，先看证据）
- `CarbonHotkeyManager.register`：打印 RegisterEventHotKey 的 OSStatus
- `CarbonHotkeyManager.installEventHandler`：打印 InstallEventHandler 的 OSStatus，
  并加 ivar `handlerInstalled` 标记
- Carbon C callback 入口加 dlog（确认 callback 是否被触发）
- DispatchQueue.main.async 内的 slot 查找成功/失败都打 dlog

### 第 2 步（如果发现是冲突或没回调）
准备 `NSEvent.addGlobalMonitorForEvents` fallback：
- 默认仍走 Carbon
- 启动 5 秒后如果 Carbon callback 从未触发，**不**自动启用 fallback（避免误判）
- 在设置页加按钮 "改用辅助功能热键"，启用后用 NSEvent 监听（需要"输入监控"授权）

## 修复尝试记录

### 尝试 1 (本次会话, 2026-05-27) — 状态: 已落地，等用户复现取证

- 方案:
  1. `CarbonHotkeyManager.register`: 检查 `RegisterEventHotKey` 的 OSStatus；非 noErr 时
     用 OPCLogger.error 上报（会自动写到 Notion Error Logs）并返回 nil。
  2. `CarbonHotkeyManager.installEventHandler`: 同上检查 `InstallEventHandler` OSStatus，
     失败时 error 上报；增加 `handlerInstalled` / `handlerInstallStatus` ivar。
  3. Carbon C callback 入口加 `[CB] entry id=... kind=PRESSED/RELEASED` 日志。
     这条 log 是关键 — 用户按键后**这条不出现**就说明 Carbon 根本没派发事件
     （= 系统抢占 / 注册失败）。
  4. callback 内 slot 查找成功 / 失败都打 log。
  5. AppDelegate.setupHotkey: register 返回 nil 时打 error，并带"Option+Space 可能被系统
     输入法切换占用"的人话提示；末尾 log 一次 `currentRegistrationsSnapshot()`。
  6. 启动 6 秒后做一次自检：如果 `callbackEverFired == false` 就 warn 提示用户。
  7. AppDelegate 的 onPress / onRelease 闭包入口也加诊断日志，确认 self 不为 nil。
- 不动业务逻辑（handleOptSpacePress / Release / Backtick 完全没改）。
- 目的: 让下一次用户按键复现时，日志能精确指出断点在哪一层。
- 验收日志关键词（按链路从外到内）：
  - `[hotkey] [HOTKEY-DIAG] [register] OK id=... keyCode=49` ← 注册成功
  - `[hotkey] [HOTKEY-DIAG] [installEventHandler] OK` ← handler 装上
  - `[hotkey] [CB] entry id=... kind=PRESSED` ← Carbon 派发事件到 App
  - `[hotkey] [CB] invoke onPress id=... keyCode=49` ← slot 找到、回调要触发
  - `[hotkey] [HOTKEY-DIAG] onPress closure fired for Opt+Space, self=alive`
  - `[hotkey] [HOTKEY] Short press - toggle panel` ← 业务函数执行
- 预期诊断：用户按键后日志会有以下其中一种 pattern：
  - **A** 完全没 `[CB] entry` → Carbon 事件根本没派发给 App
    - 子情况 A1: register 直接返回 nil，会有 ERROR 日志说 status=多少
      （-9878 = eventHotKeyExistsErr，被占用）
    - 子情况 A2: register OK 但运行时被抢占（典型：用户系统设置里输入法切换占用了 Option+Space）
  - **B** 有 `[CB] entry` 但没 `slot NOT FOUND` 也没 `invoke onPress` →
    DispatchQueue.main.async 后没执行（runloop 卡？罕见）
  - **C** 有 `invoke onPress` 但没 `onPress closure fired` → 闭包没被调（不太可能）
  - **D** 有 `onPress closure fired` 但 self=nil → AppDelegate 释放了（不太可能）
  - **E** 有 `onPress closure fired self=alive` 但没 `[HOTKEY] Short press` →
    handleOptSpacePress 内部死锁（看 lastSpaceKeyDownAt 去抖逻辑）

## 关于 NSEvent.addGlobalMonitorForEvents fallback

用户在任务描述里提到：「如果你最终断定 Carbon HotKey 在当前 macOS 版本根本走不通，
可以加一个 NSEvent.addGlobalMonitorForEvents 的备选路径」。

**本轮没加 fallback**，原因：
1. 还没有证据证明 Carbon 完全不行——register 调用本身在历史日志里没失败提示
2. NSEvent.addGlobalMonitorForEvents 需要"输入监控"系统权限，沉默失败的话用户不会察觉，
   反而让排查更糊
3. 应该先用现在加的诊断日志定位是哪个具体环节坏的，再决定要不要 fallback

如果用户按完热键、日志显示 pattern A2（典型：输入法占用），最直接的修复是引导用户去
「系统设置 → 键盘 → 文本输入 → 输入法 → 编辑」关掉 Option+Space 切换源；或者改用
其他不冲突的快捷键组合（例如 Option+Shift+Space）。

---

## 真正的根因（运行时证据揭示）

接入诊断日志后，用户复现了一次完整序列（`~/.opc-companion/logs/2026-05-27.log`）：

```
14:51:31  Carbon hotkey 注册成功 status=0
14:51:37  6s self-check: callback has NOT fired yet
   ↓ 12 分钟空白，用户什么都没动（用户原话："什么都没动过几分钟就好了"）
15:03:30  突然开始工作：[CB] entry → invoke onPress → showPanel（全链路 OK）
```

`RegisterEventHotKey` 是 noErr、`InstallEventHandler` 是 noErr、`callbackEverFired` 启动后
12 分钟仍为 false、用户没改任何系统设置 → **"系统输入法切换占用"假设被削弱**
（关掉之后才会恢复，不会自动恢复）。

**最强嫌疑：macOS Secure Event Input mode 在那 12 分钟内被某个外部进程启用了。**

典型触发源：
- 终端跑 `sudo` / `ssh` 输入密码（Terminal / iTerm2）
- 网页里输入密码字段（浏览器 Safari/Chrome 把 Secure Input 推到系统）
- 1Password / Bitwarden 等密码管理器解锁界面
- macOS 锁屏密码输入

任意上述情景下，`IsSecureEventInputEnabled()` 返回 true，第三方全局热键（无论 Carbon
还是 NSEvent global monitor）都被系统屏蔽。等触发进程失焦后状态自动解除。
这与「12 分钟后无任何操作突然好用」完全吻合。

App 无法直接消除 Secure Input（这是系统级安全机制），只能：
1. 监测 `IsSecureEventInputEnabled()` 实时状态
2. 用户可见的 Banner 提示「你看不见的原因是 Secure Input 在屏蔽热键」
3. 给用户一个一键重注册的兜底

## 修复方案（本轮交付）

### 1. CarbonHotkeyManager
- 新增 `static func isSecureInputEnabled() -> Bool` 暴露 `IsSecureEventInputEnabled()`
- `currentRegistrationsSnapshot()` 加上 `secureInput=...` 字段
- C callback 首次 fire 时通过 `DispatchQueue.main.async` 通知 `HotkeyHealthMonitor`
  清掉警告 banner

### 2. HotkeyHealthMonitor（新文件 Utils/HotkeyHealthMonitor.swift）
- 启动 6s 自检；若 `callbackEverFired == false`：
  - case A `IsSecureEventInputEnabled() == true` → Banner（warning, 8s）：
    「系统启用了安全输入（某个 App 在接收密码），全局热键暂时无效。等那个 App 失焦后会自动恢复。」
  - case B Secure Input == false 但 callback 也没 fire → Banner（warning, 8s）：
    「全局热键无响应。可能被其他 App（Alfred / Raycast / 启动器）抢占，或系统输入法占用了 Opt+Space。」
- 之后每 5s 重检一次，最多 6 次（启动后 36s 内）；callback 首次 fire 时立刻清掉
  warning，发一条 success banner（3s）「全局热键已恢复」

### 3. 设置页「全局热键诊断」section
- 实时显示：Carbon 回调已触发过 / Secure Input 是否启用 / `currentRegistrationsSnapshot()`
- 按钮「重新注册热键」→ 调 `AppDelegate.reregisterHotkeys()`（unregisterAll + 重新跑 register）
- 文字提示常见冲突源 + 排查路径

### 4. 日志降级（任务 2 顺手做）
- 删除 onPress / onRelease closure-fired 诊断行（每次按键 2-4 条）
- 删除 `[CB] invoke onPress/onRelease`、`[register] enter`、`[unregister]`、`[unregisterAll]` 等冗余 INFO
- 删除 `handleOptSpacePress` / `Release` / `Backtick` 内的 `[HOTKEY] xxx` 业务日志
- 保留的关键 milestone：`[register] OK`、`[CB] entry`、`Snapshot`、`[secure-input] check`、
  注册失败 / installEventHandler 失败的 ERROR、6s 自检 WARN 还在但通过 monitor 触发

## 未来如果复发的排查路径

1. **先看顶部 Banner**：启动后 6-36s 内会自动推
   - 「系统启用了安全输入...」→ 找到正在接收密码的 App（终端 / 浏览器密码字段 / 密码管理器），
     让它失焦或退出该界面
   - 「全局热键无响应...」→ 检查 Alfred / Raycast / 输入法
2. **再看设置页**：「全局热键诊断」section 实时显示状态，按「重新注册热键」一键重试
3. **最后 grep 日志**：`tail -f ~/.opc-companion/logs/<日期>.log | grep '\[hotkey\]'`
   - 没有 `[CB] entry` → 系统抢占（Secure Input 或输入法）
   - 有 `[CB] entry` 但没业务执行 → 看 `slot NOT FOUND` 或主线程派发问题
   - 有 `RegisterEventHotKey FAILED status=-9878` → eventHotKeyExistsErr，另一个 App 已注册

## 关于 NSEvent fallback

仍然没加。理由不变 + 新增一条：fallback 也吃 Secure Input，加了等于白加；遇到
Secure Input 唯一正解是让用户感知到「不是 App 坏了，是系统在屏蔽」，本轮的 Banner +
设置页诊断正是干这个的。
