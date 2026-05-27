import Cocoa

let args = CommandLine.arguments

// Optional subtitle: all args after program name joined
var subtitle = ""
if args.count >= 2 {
    subtitle = args.dropFirst().joined(separator: " ")
}

// Accessory app — no dock icon, no menu bar
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Panel metrics
let panelW: CGFloat = 300
let panelH: CGFloat = 64
let margin: CGFloat = 20
let radius: CGFloat = 14

let panel = NSPanel(
    contentRect: NSRect(x: 0, y: 0, width: panelW, height: panelH),
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
panel.isOpaque = false
panel.backgroundColor = .clear
panel.level = .floating
panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
panel.hasShadow = true

// Frosted-glass background
let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: panelW, height: panelH))
effect.material = .menu
effect.blendingMode = .behindWindow
effect.state = .active
effect.wantsLayer = true
effect.layer?.cornerRadius = radius
effect.layer?.masksToBounds = true
panel.contentView?.addSubview(effect)

// Green checkmark icon (SF Symbol)
let iconSize: CGFloat = 28
let iconY = (panelH - iconSize) / 2
let iconView = NSImageView(frame: NSRect(x: 16, y: iconY, width: iconSize, height: iconSize))
if let img = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil) {
    let cfg = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .medium)
    iconView.image = img.withSymbolConfiguration(cfg)
    iconView.contentTintColor = NSColor.systemGreen
}
effect.addSubview(iconView)

// Title: "截图已保存"
let titleLabel = NSTextField(labelWithString: "截图已保存")
titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
titleLabel.textColor = .labelColor
let titleY: CGFloat = subtitle.isEmpty ? (panelH - 18) / 2 : 36
titleLabel.frame = NSRect(x: 56, y: titleY, width: panelW - 72, height: 18)
effect.addSubview(titleLabel)

// Subtitle: app name / optional detail
let subLabel = NSTextField(labelWithString: subtitle)
subLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
subLabel.textColor = .secondaryLabelColor
subLabel.frame = NSRect(x: 56, y: 14, width: panelW - 72, height: 16)
subLabel.lineBreakMode = .byTruncatingTail
effect.addSubview(subLabel)

// Position top-right of main screen
if let screen = NSScreen.main {
    let frame = screen.visibleFrame
    let x = frame.maxX - panelW - margin
    let y = frame.maxY - panelH - margin
    panel.setFrameOrigin(NSPoint(x: x, y: y))
}

// Fade in
panel.alphaValue = 0
panel.orderFront(nil)
NSAnimationContext.runAnimationGroup { ctx in
    ctx.duration = 0.3
    panel.animator().alphaValue = 1.0
}

// Auto-dismiss with fade-out after 2s
DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
    NSAnimationContext.runAnimationGroup({ ctx in
        ctx.duration = 0.4
        panel.animator().alphaValue = 0.0
    }, completionHandler: {
        panel.close()
        NSApp.terminate(nil)
    })
}

app.run()
