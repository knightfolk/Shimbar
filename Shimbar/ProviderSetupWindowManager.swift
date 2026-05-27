// MARK: - ProviderSetupWindowManager.swift
// Shimbar – Manages standalone window hosting for the ProviderSetupWizard
// macOS 14+

import AppKit
import SwiftUI

@MainActor
class ProviderSetupWindowManager {
    static let shared = ProviderSetupWindowManager()
    
    private var window: NSWindow?
    private var delegate: NSWindowDelegate?
    
    private init() {}
    
    /// Present the setup wizard in a standalone utility window
    func show(manager: ShimManager) {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let setupView = ProviderSetupWizard()
            .environment(manager)
            .frame(width: 580, height: 500)
        
        let hostingView = NSHostingView(rootView: setupView)
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 500),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.title = "Add a Provider"
        newWindow.contentView = hostingView
        newWindow.center()
        
        // Offset 50 pixels to the left to prevent overlapping with the menu popover
        var windowFrame = newWindow.frame
        windowFrame.origin.x -= 50
        newWindow.setFrame(windowFrame, display: true)
        
        newWindow.isReleasedWhenClosed = false
        
        // Setup close delegate to clean up reference
        let closeDelegate = SetupWindowDelegate()
        newWindow.delegate = closeDelegate
        self.delegate = closeDelegate
        
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        self.window = newWindow
    }
    
    func close() {
        window?.close()
        window = nil
        delegate = nil
    }
    
    func clearWindowReference() {
        self.window = nil
        self.delegate = nil
    }
}

// MARK: - SetupWindowDelegate

private class SetupWindowDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            ProviderSetupWindowManager.shared.clearWindowReference()
        }
    }
}
