#!/usr/bin/env osascript -l JavaScript
// AppshotNotify - Apple-style overlay notification via JXA
// Usage: osascript -l JavaScript notify.js "App Name" "/path/to/icon.png"
ObjC.import('Cocoa');

var args = $.NSProcessInfo.processInfo.arguments;
var subtitle = "";
var iconPath = "";

for (var i = 2; i < args.count; i++) {
    var p = ObjC.unwrap(args.objectAtIndex(i));
    if (p && p.length > 0) {
        if (p.indexOf('.png') >= 0 || p.indexOf('.PNG') >= 0) {
            iconPath = p;
        } else {
            subtitle += (subtitle ? " " : "") + p;
        }
    }
}

var app = $.NSApplication.sharedApplication;
app.setActivationPolicy($.NSApplicationActivationPolicyAccessory);

var PW = 300, PH = 64, M = 20;

var panel = $.NSPanel.alloc.initWithContentRectStyleMaskBackingDefer(
    $.NSMakeRect(0, 0, PW, PH),
    $.NSWindowStyleMaskBorderless | $.NSWindowStyleMaskNonactivatingPanel,
    $.NSBackingStoreBuffered, false
);
panel.opaque = false;
panel.backgroundColor = $.NSColor.whiteColor;
panel.level = $.NSFloatingWindowLevel;
panel.collectionBehavior = $.NSWindowCollectionBehaviorCanJoinAllSpaces | $.NSWindowCollectionBehaviorStationary;
panel.hasShadow = true;

// Solid white rounded background
var bg = $.NSView.alloc.initWithFrame($.NSMakeRect(0, 0, PW, PH));
bg.wantsLayer = true;
bg.layer.backgroundColor = $.NSColor.whiteColor.CGColor;
bg.layer.cornerRadius = 14;
bg.layer.masksToBounds = true;
panel.contentView.addSubview(bg);

// Icon: use custom PNG if available, fall back to SF Symbol
var iconSize = 28, iconY = (PH - iconSize) / 2;
var iv = $.NSImageView.alloc.initWithFrame($.NSMakeRect(16, iconY, iconSize, iconSize));
iv.imageScaling = $.NSImageScaleProportionallyUpOrDown;

var customIcon = null;
if (iconPath.length > 0) {
    customIcon = $.NSImage.alloc.initWithContentsOfFile($(iconPath));
}

if (customIcon) {
    iv.image = customIcon;
} else {
    var fallback = $.NSImage.imageWithSystemSymbolNameAccessibilityDescription($("checkmark.circle.fill"), $());
    if (fallback) {
        iv.image = fallback.imageWithSymbolConfiguration(
            $.NSImageSymbolConfiguration.configurationWithPointSizeWeight(iconSize, 0.23)
        );
        iv.contentTintColor = $.NSColor.systemGreenColor;
    }
}
bg.addSubview(iv);

// Title
var showSub = subtitle.length > 0;
var ty = showSub ? 36 : (PH - 18) / 2;
var tl = $.NSTextField.alloc.initWithFrame($.NSMakeRect(56, ty, PW - 72, 18));
tl.stringValue = $("截图已保存");
tl.font = $.NSFont.systemFontOfSizeWeight(14, 0.38);
tl.textColor = $.NSColor.labelColor;
tl.bezeled = false; tl.drawsBackground = false; tl.editable = false; tl.selectable = false;
bg.addSubview(tl);

if (showSub) {
    var sl = $.NSTextField.alloc.initWithFrame($.NSMakeRect(56, 14, PW - 72, 16));
    sl.stringValue = $(subtitle);
    sl.font = $.NSFont.systemFontOfSizeWeight(12, 0.0);
    sl.textColor = $.NSColor.secondaryLabelColor;
    sl.bezeled = false; sl.drawsBackground = false; sl.editable = false; sl.selectable = false;
    sl.lineBreakMode = $.NSLineBreakByTruncatingTail;
    bg.addSubview(sl);
}

// Position top-right
var sf = $.NSScreen.mainScreen.visibleFrame;
panel.setFrameOrigin($.NSMakePoint(sf.origin.x + sf.size.width - PW - M, sf.origin.y + sf.size.height - PH - M));

// Fade in
panel.alphaValue = 0;
panel.orderFront($());
panel.animator.alphaValue = 1.0;

// Wait 2.5s
var start = $.NSDate.date;
while (($.NSDate.date.timeIntervalSinceDate(start)) < 2.5) {
    $.NSRunLoop.mainRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(0.1));
}

// Fade out
panel.animator.alphaValue = 0.0;
var start2 = $.NSDate.date;
while (($.NSDate.date.timeIntervalSinceDate(start2)) < 0.5) {
    $.NSRunLoop.mainRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(0.1));
}

panel.orderOut($());
