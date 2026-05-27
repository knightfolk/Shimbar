// MARK: - OnboardingWindowManager.swift
// Shimbar – Coordinates AppKit hosting of OnboardingView
// macOS 14+

import AppKit
import SwiftUI

@MainActor
class OnboardingWindowManager {
    static let shared = OnboardingWindowManager()
    
    private var window: NSWindow?
    
    private init() {}
    
    /// Display the onboarding/diagnostics window programmatically
    func show(manager: ShimManager) {
        // If already visible, focus it and bring it to front
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let onboardingView = OnboardingView(onCompletion: { [weak self] in
            self?.close()
        })
        .environment(manager)
        .frame(minWidth: 580, maxWidth: 800, minHeight: 500, maxHeight: 700)
        
        let hostingView = NSHostingView(rootView: onboardingView)
        
        // Define clean, native macOS window style
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.title = "Shimbar Onboarding & Diagnostics"
        newWindow.contentView = hostingView
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.makeKeyAndOrderFront(nil)
        
        // Make the app frontmost to ensure window displays properly on launch
        NSApp.activate(ignoringOtherApps: true)
        
        self.window = newWindow
    }
    
    /// Close the onboarding window
    func close() {
        window?.close()
        window = nil
    }
}
