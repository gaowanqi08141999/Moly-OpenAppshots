#!/usr/bin/env osascript -l JavaScript
// Moly Notify - Apple-style overlay notification via JXA
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

// 1.5x scale: 450×96 panel, 30px margin
var PW = 450, PH = 96, M = 30, R = 20;
var fontSize = 18, subFontSize = 14, iconSize = 42;

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
bg.layer.cornerRadius = R;
bg.layer.masksToBounds = true;
panel.contentView.addSubview(bg);

// Icon
var iconY = (PH - iconSize) / 2;
var iv = $.NSImageView.alloc.initWithFrame($.NSMakeRect(20, iconY, iconSize, iconSize));
iv.imageScaling = $.NSImageScaleProportionallyUpOrDown;

var customIcon = null;
if (iconPath.length > 0) {
    var iconData = $.NSData.dataWithContentsOfFile($(iconPath));
    if (iconData) {
        customIcon = $.NSImage.alloc.initWithData(iconData);
    }
}
var iconValid = false;
if (customIcon) {
    try { iconValid = (customIcon.size && customIcon.size.width > 0); } catch(e) {}
}
if (iconValid) {
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
var textX = 76;
var textW = PW - textX - 20;
var ty = showSub ? PH - 42 : (PH - fontSize - 4) / 2;
var tl = $.NSTextField.alloc.initWithFrame($.NSMakeRect(textX, ty, textW, fontSize + 4));
tl.stringValue = $("截图已保存");
tl.font = $.NSFont.systemFontOfSizeWeight(fontSize, 0.38);
tl.textColor = $.NSColor.labelColor;
tl.bezeled = false; tl.drawsBackground = false; tl.editable = false; tl.selectable = false;
bg.addSubview(tl);

if (showSub) {
    var sl = $.NSTextField.alloc.initWithFrame($.NSMakeRect(textX, 18, textW, subFontSize + 4));
    sl.stringValue = $(subtitle);
    sl.font = $.NSFont.systemFontOfSizeWeight(subFontSize, 0.0);
    sl.textColor = $.NSColor.secondaryLabelColor;
    sl.bezeled = false; sl.drawsBackground = false; tl.editable = false; tl.selectable = false;
    sl.lineBreakMode = $.NSLineBreakByTruncatingTail;
    bg.addSubview(sl);
}

// Position top-right
var sf = $.NSScreen.mainScreen.visibleFrame;
panel.setFrameOrigin($.NSMakePoint(sf.origin.x + sf.size.width - PW - M, sf.origin.y + sf.size.height - PH - M));

// Show instantly (no animator delay — faster)
panel.orderFront($());
panel.alphaValue = 1.0;

// Display duration
var start = $.NSDate.date;
while (($.NSDate.date.timeIntervalSinceDate(start)) < 2.0) {
    $.NSRunLoop.mainRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(0.05));
}

// Quick fade out
panel.animator.alphaValue = 0.0;
var start2 = $.NSDate.date;
while (($.NSDate.date.timeIntervalSinceDate(start2)) < 0.3) {
    $.NSRunLoop.mainRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(0.05));
}

panel.orderOut($());
