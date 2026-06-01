# moly — Appshots 复现规划

> 目标：在 macOS 平台上复现 OpenAI Codex Appshots 功能，实现双击快捷键捕获当前窗口的截图 + 结构化文本，并与智能体架构集成。

---

## 一、总体架构

```
┌─────────────────────────────────────────────────────────┐
│                    产品 UI 层                            │
│   ┌─────────────┐  ┌──────────────┐  ┌───────────────┐  │
│   │ 快捷键监听    │  │ 快照浏览器     │  │ Agent 对话面板  │  │
│   │ (全局热键)   │  │ (历史回看)     │  │ (AI 交互)     │  │
│   └──────┬──────┘  └──────┬───────┘  └───────┬───────┘  │
└──────────┼────────────────┼──────────────────┼──────────┘
           │                │                  │
           ▼                ▼                  ▼
┌─────────────────────────────────────────────────────────┐
│                   核心服务层 (Rust / Swift)               │
│                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────┐  │
│  │CaptureEngine │  │StorageEngine │  │  AgentBridge  │  │
│  │ 捕获引擎      │  │ 存储引擎      │  │  智能体桥接    │  │
│  └──────┬───────┘  └──────┬───────┘  └───────┬───────┘  │
└─────────┼─────────────────┼──────────────────┼──────────┘
          │                 │                  │
          ▼                 ▼                  ▼
┌──────────────────┐ ┌──────────────┐ ┌──────────────────┐
│ 系统 API 层       │ │ 本地文件系统   │ │ MCP / HTTP /     │
│                  │ │              │ │ WebSocket        │
│ ScreenCaptureKit │ │ ~/snapshots/ │ │ → LLM Provider   │
│ Accessibility    │ │   YYYY-MM-DD/│ │                  │
│ CGWindowList     │ │   app-name/  │ │                  │
│                  │ │   timestamp/ │ │                  │
└──────────────────┘ └──────────────┘ └──────────────────┘
```

核心思想：**捕获、存储、消费** 三层解耦，每一层可独立替换和演进。

---

## 二、核心架构：双层捕获机制

这是 Appshots 最关键的实现细节 —— 它**不是**简单的截图 + OCR，而是两个并行的捕获管线：

```
用户按下快捷键
       │
       ▼
┌──────────────────────────────────────┐
│  Window Server / CoreGraphics        │
│  识别前台活跃窗口 (NSWindow)          │
└──────────┬───────────────────────────┘
           │
    ┌──────┴──────┐
    ▼              ▼
┌──────────────┐  ┌─────────────────────┐
│ 视觉层        │  │ 文本/结构层           │
│              │  │                     │
│ ScreenCapture│  │ Accessibility API   │
│ Kit          │  │ (AXUIElement 树)    │
│              │  │                     │
│ → 高清 PNG   │  │ → 结构化文本树       │
│   截图       │  │ → UI 元素结构        │
│              │  │ → 可见+不可见文本     │
│              │  │ → 文件路径/URL等元数据│
└──────────────┘  └─────────────────────┘
           │              │
           └──────┬───────┘
                  ▼
          组合后的 Payload
          附加到 Agent 对话线程
```

### 第1层：视觉捕获 — `ScreenCaptureKit`

- 使用 Apple 原生 **ScreenCaptureKit** 框架（要求 macOS 12.3+）
- **只捕获前台活跃窗口**，自动裁剪掉桌面背景、其他窗口、菜单栏等无关元素
- 产出高保真 PNG 截图，AI 可分析布局、设计稿、终端颜色等视觉信息
- 需要 **"屏幕与系统音频录制"** 权限

### 第2层：语义文本捕获 — `Accessibility API`（关键创新）

- 使用 macOS 的 **Accessibility 框架**读取应用的 **Accessibility Tree**
- 这个 Tree 是应用向辅助技术（如 VoiceOver）暴露的 UI 元素结构化表示
- **关键区别**：这不是 OCR。OCR 是"看图识字"，准确率受限且只能识别可见文字。而 Accessibility API 直接读取应用内部数据结构中的文本：
  - **可以捕获滚动区域中被遮挡、屏幕上看不到的文本**
  - **可以捕获长终端输出的完整内容**
  - **可以获取网页 DOM 中未渲染到视口的文本**
  - 准确率 100%（因为读的是结构数据，不存在识别错误）

---

## 三、存储结构

本地文件存储格式：

```
~/snapshots/
└── 2026-05-25/
    └── VS Code-14:32:05/
        ├── screenshot.png          # 高保真截图
        ├── metadata.json           # 元数据
        └── accessibility_tree.json # 结构化文本
```

### metadata.json 结构

```json
{
  "id": "snap_20260525_143205",
  "timestamp": "2026-05-25T14:32:05+08:00",
  "app": {
    "bundle_id": "com.microsoft.VSCode",
    "name": "Visual Studio Code",
    "window_title": "app.ts — my-project",
    "pid": 12345
  },
  "window_bounds": {
    "x": 0,
    "y": 38,
    "width": 1920,
    "height": 1042
  },
  "image": {
    "path": "screenshot.png",
    "width": 3840,
    "height": 2084,
    "scale_factor": 2.0,
    "format": "png"
  },
  "accessibility": {
    "path": "accessibility_tree.json",
    "text_length": 2847,
    "element_count": 156
  }
}
```

存储方案建议：
- **文件系统** 存大文件（PNG + JSON）
- **SQLite** 存元数据索引（时间、应用、窗口标题、文本摘要）用于快速搜索
- 自动清理策略：默认保留 7 天，用户可配置

---

## 四、捕获引擎详细实现 (Swift)

```swift
import ScreenCaptureKit
import ApplicationServices

class AppshotCaptureEngine {

    // ── 1. 获取前台窗口 ──
    func captureFrontmostWindow() async throws -> AppshotPayload {
        // 获取前台应用
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            throw AppshotError.noActiveApplication
        }

        // 获取窗口列表，找到前台应用的主窗口
        let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as! [[String: Any]]

        guard let targetWindow = windowList.first(where: {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == frontApp.processIdentifier
        }) else {
            throw AppshotError.noVisibleWindow
        }

        // ── 2. 并行捕获：视觉 + 文本 ──
        async let screenshot = captureWindow(
            windowID: targetWindow[kCGWindowNumber as String] as! CGWindowID)
        async let axTree      = extractAccessibilityTree(pid: frontApp.processIdentifier)
        async let appMeta     = buildAppMetadata(app: frontApp, window: targetWindow)

        let (image, textTree, metadata) = try await (screenshot, axTree, appMeta)

        // ── 3. 组装 payload ──
        return AppshotPayload(
            metadata: metadata,
            screenshot: image,
            accessibilityTree: textTree
        )
    }

    // ── ScreenCaptureKit 截图 ──
    private func captureWindow(windowID: CGWindowID) async throws -> NSImage {
        let shareableContent = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )

        guard let window = shareableContent.windows.first(where: {
            $0.windowID == windowID
        }) else {
            throw AppshotError.windowNotFound
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width * 2)   // Retina 2x
        config.height = Int(window.frame.height * 2)
        config.scalesToFit = false
        config.capturesAudio = false
        config.showsCursor = true

        return try await captureSingleFrame(filter: filter, config: config)
    }

    // ── Accessibility API 提取文本树 ──
    private func extractAccessibilityTree(pid: pid_t) throws -> AXNode {
        let appElement = AXUIElementCreateApplication(pid)

        func traverse(_ element: AXUIElement, depth: Int) -> AXNode {
            var node = AXNode(
                role: element.attribute(kAXRoleAttribute),
                title: element.attribute(kAXTitleAttribute),
                value: element.attribute(kAXValueAttribute),
                description: element.attribute(kAXDescriptionAttribute),
                children: []
            )

            guard depth < 20 else { return node }

            if let children = element.attribute(kAXChildrenAttribute) as? [AXUIElement] {
                for child in children.prefix(500) {
                    node.children.append(traverse(child, depth: depth + 1))
                }
            }

            return node
        }

        return traverse(appElement, depth: 0)
    }
}
```

---

## 五、与智能体架构的集成

把捕获能力封装成工具（Tool），让 Agent 在需要时调用。在 MCP 框架下的实现：

```
┌──────────────────────────────────────────┐
│              MCP Server                   │
│                                           │
│  tools:                                   │
│    - take_screenshot(app_name?)           │
│    - list_appshots(filter?)               │
│    - get_appshot_text(snapshot_id)        │
│    - compare_screenshots(id1, id2)        │
│                                           │
└──────────────┬───────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────┐
│          产品 Agent 循环                   │
│                                           │
│  while True:                              │
│    user_input = ui.get_input()            │
│    context = build_context()              │
│      ├── 对话历史                         │
│      ├── 当前文件内容                     │
│      └── 最新 Appshot（截图+文本）          │  ← 自动注入
│                                           │
│    response = llm.chat(context)           │
│                                           │
│    if response.tool_call == "take_snapshot":│
│      payload = capture_engine.capture()   │
│      storage.save(payload)                │
│      continue  # 带着新快照继续对话        │
│                                           │
│    ui.display(response)                   │
```

### Agent 集成层次

| 层次 | 做法 | 适用场景 |
|------|------|----------|
| **L1: 纯上下文注入** | 把截图+文本作为多模态消息发给 LLM | 最简 MVP，验证概念 |
| **L2: MCP 工具暴露** | 把快照能力封装成 MCP tool，Agent 可主动调用 | 让 AI 自己决定何时截屏 |
| **L3: 完整 Agent 循环** | 截图 → AI 分析 → 执行操作 → 再截图验证 | 全自动工作流 |

---

## 六、存储引擎设计 (Rust)

```rust
struct SnapshotStorage {
    base_path: PathBuf,  // ~/snapshots/
    db: SqliteConnection, // 元数据索引
}

impl SnapshotStorage {
    // 保存一份快照
    fn save(&self, payload: AppshotPayload) -> Result<SnapshotId> {
        let dir = self.base_path
            .join(payload.timestamp.format("%Y-%m-%d"))
            .join(sanitize(&payload.app_name))
            .join(payload.timestamp.format("%H-%M-%S"));

        fs::create_dir_all(&dir)?;
        payload.screenshot.save(dir.join("screenshot.png"))?;
        fs::write(
            dir.join("accessibility_tree.json"),
            serde_json::to_string_pretty(&payload.ax_tree)?
        )?;
        fs::write(
            dir.join("metadata.json"),
            serde_json::to_string_pretty(&payload.metadata)?
        )?;

        self.db.execute("INSERT INTO snapshots ...")?;
        Ok(SnapshotId::new())
    }

    // 按时间、应用名、关键词搜索历史快照
    fn query(&self, filter: SnapshotFilter) -> Vec<SnapshotSummary> { ... }

    // 获取完整快照内容
    fn get_full(&self, id: SnapshotId) -> Result<AppshotPayload> { ... }

    // 清理 N 天前的旧快照
    fn prune(&self, older_than_days: u32) -> Result<usize> { ... }
}
```

---

## 七、实现路线图

```
Phase 1 (1-2 周): 最小可行
  ├── macOS ScreenCaptureKit 单帧截图
  ├── Accessibility Tree 提取
  ├── 本地文件保存 (PNG + JSON)
  ├── 命令行工具验证
  └── 效果：敲一个命令，截图+文本落地到 ~/snapshots/

Phase 2 (1-2 周): UI + Agent
  ├── 全局快捷键监听
  ├── 历史快照浏览器 UI
  ├── 多模态消息发送给 LLM (screenshot base64 + text)
  └── 效果：按快捷键 → 截图 → AI 分析结果出现在对话面板

Phase 3 (1-2 周): 自动化
  ├── 封装为 MCP tools
  ├── Agent 主动调用截图
  ├── 截图对比 (before/after diff)
  └── 效果：AI 写代码 → 自动截图浏览器 → 发现 UI 不对 → 自动修复
```

---

## 八、概念验证 Demo (Python)

```python
#!/usr/bin/env python3
"""最简 Appshot 概念验证 — macOS only"""
import subprocess, json, time, os
from datetime import datetime
from pathlib import Path
import base64

SNAPSHOT_DIR = Path.home() / "snapshots"

def capture_macos():
    """核心捕获逻辑"""
    timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")

    # 1. 获取前台应用信息 (AppleScript)
    frontmost = subprocess.run([
        "osascript", "-e",
        'tell app "System Events" to get {name, bundle identifier} '
        'of first process whose frontmost is true'
    ], capture_output=True, text=True).stdout.strip()
    app_name, bundle_id = frontmost.split(", ", 1)

    # 2. 截图 (screencapture 命令)
    img_path = SNAPSHOT_DIR / timestamp / "screenshot.png"
    img_path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["screencapture", "-w", "-x", str(img_path)], check=True)

    # 3. 提取 accessible 文本 (AppleScript + System Events)
    text = subprocess.run([
        "osascript", "-e",
        '''
        tell application "System Events"
            set frontProcess to first process whose frontmost is true
            set uiElems to entire contents of front window of frontProcess
            set output to ""
            repeat with elem in uiElems
                try
                    set output to output & (value of elem) & return
                end try
            end repeat
            return output
        end tell
        '''
    ], capture_output=True, text=True).stdout

    # 4. 保存文件
    text_path = img_path.parent / "accessibility_text.txt"
    text_path.write_text(text)

    meta = {
        "timestamp": timestamp,
        "app_name": app_name,
        "bundle_id": bundle_id,
        "image": str(img_path),
        "text": str(text_path),
        "text_length": len(text)
    }
    (img_path.parent / "metadata.json").write_text(json.dumps(meta, indent=2))

    print(f"✅ Appshot captured: {app_name}")
    print(f"   Image: {img_path}")
    print(f"   Text:  {len(text)} chars extracted")
    return meta

if __name__ == "__main__":
    capture_macos()
```

---

## 九、关键技术难点预警

1. **Accessibility Tree 可能非常巨大**
   - 一个 VS Code 窗口可能有 3000+ 个 AX 节点，层级深度 20+
   - 不加限制的话遍历卡死或 OOM
   - 需要设置 max_depth (建议 20) 和 max_children (建议 500) 限制

2. **截图 + AX 树之间有时间差**
   - 两个捕获 API 不是原子调用，中间可能产生几毫秒的差异
   - 如果用户在快速切换窗口，可能截到应用 A 的图但拿到应用 B 的文本
   - 需要用 PID + Window ID 做交叉校验

3. **部分应用不暴露 Accessibility Tree**
   - 部分 Electron 应用虽然支持 AX，但文本质量因应用而异
   - 需要用 OCR (如 macOS Vision 框架) 做 fallback

4. **Retina 屏幕截图文件体积大**
   - 3840×2084 PNG 约 5-15MB
   - 发送给 LLM 前需要缩放（限制 max 2048px 宽）+ JPEG 压缩

---

## 十、权限配置

| 权限 | 用途 |
|------|------|
| **Screen & System Audio Recording** | ScreenCaptureKit 截图 |
| **Accessibility** | 遍历应用 Accessibility Tree 提取文本 |

首次使用时通过标准 macOS 授权弹窗获取。需在 `Info.plist` 中配置：
- `NSScreenCaptureUsageDescription`
- `NSAppleEventsUsageDescription`

---

## 十一、后续扩展方向

- [ ] Windows 平台支持 (DXGI Desktop Duplication + UI Automation)
- [ ] Linux 平台支持 (PipeWire + AT-SPI2)
- [ ] 视频录制模式（连续截图 → 时间线回放）
- [ ] 与 IDE 插件深度集成（VS Code / JetBrains 扩展）
- [ ] 云端同步（团队共享快照上下文）
