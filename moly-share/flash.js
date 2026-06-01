#!/usr/bin/env osascript -l JavaScript
// Screen flash effect — called immediately on hotkey press for instant UX feedback
ObjC.import('Cocoa');

var app = $.NSApplication.sharedApplication;
app.setActivationPolicy($.NSApplicationActivationPolicyAccessory);

var screens = $.NSScreen.screens;
var count = screens.count;

for (var i = 0; i < count; i++) {
    var screen = screens.objectAtIndex(i);
    var frame = screen.frame;

    var flash = $.NSPanel.alloc.initWithContentRectStyleMaskBackingDefer(
        frame,
        $.NSWindowStyleMaskBorderless | $.NSWindowStyleMaskNonactivatingPanel,
        $.NSBackingStoreBuffered, false
    );
    flash.opaque = false;
    flash.backgroundColor = $.NSColor.whiteColor;
    flash.alphaValue = 0.45;
    flash.level = $.NSScreenSaverWindowLevel;
    flash.collectionBehavior = $.NSWindowCollectionBehaviorCanJoinAllSpaces | $.NSWindowCollectionBehaviorStationary;

    flash.orderFront($());
    flash.animator.alphaValue = 0.0;
}

// Wait for fade-out to complete (150ms)
var start = $.NSDate.date;
while (($.NSDate.date.timeIntervalSinceDate(start)) < 0.15) {
    $.NSRunLoop.mainRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(0.05));
}
