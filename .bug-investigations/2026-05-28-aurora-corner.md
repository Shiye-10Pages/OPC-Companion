# Aurora 主题主面板圆角外有浅色直角边
创建时间: 2026-05-28
状态: 调查中

## 症状
- 切到 Aurora 主题（panelCornerRadius = 26）时，主面板四个圆角外侧能看到一圈"浅色直角边"
- 颜色像浅紫白，跟 panel material 颜色类似
- 从圆角的圆弧外侧延伸到 panel 矩形 frame 真实边缘
- Stoa 主题（panelCornerRadius = 4）看不出（圆角太小，肉眼几乎察觉不到）

## 数据流路径（视图层级）

```
NSPanel (HUDPanel, styleMask=[.fullSizeContentView], backgroundColor=.clear, isOpaque=false, hasShadow=false)
  shadowWrapper: NSView (wantsLayer=true)
    layer.shadowPath = rounded(26)
    layer.masksToBounds = false (让阴影画出去)
    layer.backgroundColor 未显式设置 → 默认 nil
    effectView: NSVisualEffectView (material=.popover, blendingMode=.behindWindow, state=.active)
      maskImage = roundedMaskImage(26)              ← material backdrop 按圆角 mask
      layer.cornerRadius = 26
      layer.masksToBounds = true                    ← 注意：这只对 effectView 自己的 backgroundColor/contents 起作用
      hostingView: NSHostingView<ContentView>
        frame = effectView.bounds (矩形)
        layer 默认设置（SwiftUI 自动 wantsLayer=true）
        layer.backgroundColor 未显式设置 → 取决于 SwiftUI 内部
        ContentView (.frame(width: 760, height: 620))
          ZStack
            AuroraBackground .clipShape(rounded 26)
            BurstFlash .clipShape(rounded 26)
            MainTabView (无 clipShape，依赖父级的 frame 边界)
```

## 已排除的假设（任务描述说前 3 次尝试都没解决）

- [x] **F1**: `panel.hasShadow = false` + shadowWrapper 自绘 shadowPath → 已生效（解决了阴影锐角）但 panel material 圆角外仍漏
- [x] **F2**: `effectView.layer.cornerRadius + masksToBounds = true` → 只对 effectView 自己的 contents 有效，**对子 view（hostingView）不按圆角裁切**（masksToBounds 是按 bounds 矩形裁子 layer）
- [x] **F3**: `effectView.maskImage = roundedMaskImage` → 让 material 的 backdrop 按圆角 mask，但**只影响 effectView 自己绘制的 backdrop**，不影响其上叠加的子 view 的内容
- [x] **F4**: SwiftUI 层 ContentView 的 `background.clipShape` / `BurstFlash.clipShape` → 只裁 SwiftUI 渲染层内部的 view，**不影响 NSHostingView 这层 NSView backing**

## 当前最可能假设：A1（NSHostingView layer 矩形背景）

SwiftUI 的 `.clipShape` 只裁 SwiftUI 内部渲染层。NSHostingView 作为 SwiftUI 跟 AppKit 的边界容器，它**自己有 layer**，且 layer 是矩形 backing。

关键链条：
- `effectView.layer.masksToBounds = true` 按 **bounds（矩形）** 裁切子 layer，**不按 cornerRadius**
  → cornerRadius 只决定 effectView **自身** 的 backgroundColor / contents 怎么绘制
  → 子 view（hostingView）的 layer 仍然填满整个 effectView.bounds（矩形）
- hostingView.layer 若有任何非透明的填充（SwiftUI 内部为根视图设的 windowBackgroundColor 之类），会铺满整个矩形
- 圆角弧外那部分：material 被 maskImage 裁掉了 → 但 hostingView.layer 的矩形背景仍在 → **就是浅色直角边**

为什么颜色"像 panel material"：NSHostingView 默认 backing 是半透明系统色（在 popover material 之上叠加，看起来跟 material 几乎一样的浅紫白）。

## 8 种可能性

- **A1（最高嫌疑）**: NSHostingView 自身 layer 矩形背景 → 解释力最强
- A2: shadowWrapper layer 默认背景 → 可能存在但概率低（shadowWrapper 通常默认透明）
- A3: NSPanel 自带 chrome（即使无 .titled）→ macOS 15+ 已大幅简化，概率低
- A4: maskImage + cornerRadius + masksToBounds 同时存在导致绘制路径冲突 → 可能但通常表现为 maskImage 不生效（实际它生效了 → 排除）
- A5: visualEffectView vibrancy/emphasis 在 mask 之外 → blendingMode 是 behindWindow 不是 withinWindow，不涉及 vibrancy 叠加
- A6: SwiftUI ContentView.clipShape 应用不到 NSView 层 → 这是事实，但本身不是 bug，是上游层 A1 导致漏裁
- A7: macOS 26 SDK 新行为 → 没具体线索，先按 A1 验证
- A8: effectView frame 跟 shadowWrapper.bounds 不一致 → 检查代码：autoresizingMask = [.width, .height] 都设了，frame 一致，排除

## 修复尝试记录

### 尝试 1 (cdc4ce8 - 9fcd27a - e44cce5, 此前会话)
- 方案：见已排除的 F1-F4
- 结果：Aurora 圆角外浅色直角边仍存在
- 结论：四个修法都在 effectView 这层及以下生效，但都管不到 NSHostingView 这层的矩形 backing

### 尝试 2 (本次会话, 2026-05-28)
- 假设：A1（NSHostingView 自身 layer 矩形背景占满 effectView.bounds）
- 方案：
  1. 显式设置 `hostingView.wantsLayer = true`（保证有 layer 接管）
  2. 显式设置 `hostingView.layer.cornerRadius = panelCornerRadius`
  3. 显式设置 `hostingView.layer.masksToBounds = true`
  4. 显式设置 `hostingView.layer.backgroundColor = .clear`（双保险，避免 SwiftUI 注入的默认背景泄漏）
  5. 同时 `shadowWrapper.layer.backgroundColor = .clear` 显式透明（A2 防御）
  6. 在 AppDelegate 暴露 `panelHostingLayerView` weak ref
  7. `ContentView.syncPanelCornerRadius` 在主题切换时同步 hostingView.layer.cornerRadius
- 验证方式：build + run + 切到 Aurora 主题，肉眼看四个圆角外是否还有浅色直角边
- 编译：swift build ✅ / swift test ✅ (76 tests pass) / ./build.sh ✅
- 待用户人眼验证

## 关键技术结论（沉淀到后续排查）

NSVisualEffectView 的圆角裁切需要四件套同时生效，缺一不可：
1. `maskImage = roundedMaskImage` — 让 material 的 backdrop blur 按圆角裁
2. `layer.cornerRadius + layer.masksToBounds = true` — 让 effectView 自身的 backgroundColor/contents 按圆角裁
3. **子 view（如 NSHostingView）必须自己设 layer.cornerRadius + masksToBounds** — 否则子 view 的 layer 仍然按矩形铺满 bounds（masksToBounds 不会按 cornerRadius 裁子 layer）
4. SwiftUI 内部的 `.clipShape` — 裁 SwiftUI 渲染层的彩色背景内容

关键陷阱：**layer.masksToBounds 是按 bounds（矩形）裁子 layer，不按 cornerRadius**。
`cornerRadius` 只决定当前 layer 自己的 backgroundColor/contents 怎么绘制，对子 layer 的尺寸约束仍然是矩形 bounds。

## 涂色实验工具（保留 debug 开关，方便复发排查）

代码注释中保留以下排查方案（已 commented out，但记录方式让后续可复用）：
- 给 `hostingView.layer.backgroundColor = NSColor.systemRed.cgColor` → 红色露 = A1 坐实
- 给 `shadowWrapper.layer.backgroundColor = NSColor.systemBlue.cgColor` → 蓝色露 = A2 坐实
- 给 `effectView.isHidden = true` → 还有浅色直角则不是 effectView 自己

