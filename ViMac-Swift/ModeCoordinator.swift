//
//  ModeCoordinator.swift
//  Vimac
//
//  Created by Dexter Leng on 9/10/19.
//  Copyright © 2019 Dexter Leng. All rights reserved.
//

import Carbon
import Cocoa
import AXSwift
import RxSwift
import Segment

protocol Coordinator {
    var windowController: OverlayWindowController { get set }
}

class ModeCoordinator : Coordinator {
    let disposeBag = DisposeBag()
    
    var priorKBLayout: InputSource?
    var forceKBLayout: InputSource?
    var forceKBLayoutObservation: NSKeyValueObservation?
    
    let scrollModeKeySequence: [Character] = ["j", "k"]
    let hintModeKeySequence: [Character] = ["f", "d"]
    private let keySequenceListener: VimacKeySequenceListener
    
    var windowController: OverlayWindowController
    
    init(windowController: OverlayWindowController) {
        self.windowController = windowController

        self.keySequenceListener = VimacKeySequenceListener()
        self.keySequenceListener.start()
        
        self.forceKBLayoutObservation = observeForceKBInputSource()
        
        disposeBag.insert(keySequenceListener.scrollMode.bind(onNext: { [weak self] _ in
            self?.setScrollMode()
        }))
        
        disposeBag.insert(keySequenceListener.hintMode.bind(onNext: { [weak self] _ in
            self?.setHintMode()
        }))
    }

    func onKeySequenceTyped(sequence: [Character]) {
        if sequence == scrollModeKeySequence {
            setScrollMode()
        } else if sequence == hintModeKeySequence {
            setHintMode()
        }
    }
    
    func exitMode() {
        guard let vc = self.windowController.window?.contentViewController else {
            return
        }
        
        if self.forceKBLayout != nil {
            self.priorKBLayout?.select()
        }

        vc.view.removeFromSuperview()
        self.windowController.window?.contentViewController = nil
        self.windowController.close()
        
        keySequenceListener.start()
    }
    
    func setViewController(vc: ModeViewController, screenFrame: NSRect) {
        vc.modeCoordinator = self
        self.windowController.window?.contentViewController = vc
        self.windowController.fitToFrame(screenFrame)
        self.windowController.showWindow(nil)
        self.windowController.window?.makeKeyAndOrderFront(nil)
    }

    func setScrollMode() {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
            let focusedWindow = focusedWindow(app: frontmostApp) else {
            self.exitMode()
            return
        }
        
        // the app crashes when talking to its own accessibility server
        let isTargetVimac = frontmostApp.bundleIdentifier == Bundle.main.bundleIdentifier
        if isTargetVimac {
            self.exitMode()
            return
        }
        
        Analytics.shared().track("Scroll Mode Activated")
        
        let focusedWindowFrame = GeometryUtils.convertAXFrameToGlobal(focusedWindow.frame)
        let screenFrame = activeScreenFrame(focusedWindowFrame: focusedWindowFrame)
        
        self.priorKBLayout = InputSourceManager.currentInputSource()
        if let forceKBLayout = self.forceKBLayout {
            forceKBLayout.select()
        }
        let vc = ScrollModeViewController.init(window: focusedWindow)
        self.setViewController(vc: vc, screenFrame: screenFrame)
        
        keySequenceListener.stop()
    }
    
    func setHintMode() {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
            let focusedWindow = focusedWindow(app: frontmostApp) else {
            self.exitMode()
            return
        }
        
        // the app crashes when talking to its own accessibility server
        let isTargetVimac = frontmostApp.bundleIdentifier == Bundle.main.bundleIdentifier
        if isTargetVimac {
            self.exitMode()
            return
        }
        
        Analytics.shared().track("Hint Mode Activated")
        
        let focusedWindowFrame: NSRect = GeometryUtils.convertAXFrameToGlobal(focusedWindow.frame)
        let screenFrame = activeScreenFrame(focusedWindowFrame: focusedWindowFrame)
        
        self.priorKBLayout = InputSourceManager.currentInputSource()
        if let forceKBLayout = self.forceKBLayout {
            forceKBLayout.select()
        }

        let vc = HintModeViewController.init(app: frontmostApp, window: focusedWindow)
        self.setViewController(vc: vc, screenFrame: screenFrame)
        
        keySequenceListener.stop()
    }
    
    func observeForceKBInputSource() -> NSKeyValueObservation {
        let observation = UserDefaults.standard.observe(\.ForceKeyboardLayout, options: [.initial, .new], changeHandler: { [weak self] (a, b) in
            let id = b.newValue
            var inputSource: InputSource? = nil
            if let id = id {
                inputSource = InputSourceManager.inputSources.first(where: { $0.id == id })
            }
            self?.forceKBLayout = inputSource
        })
        return observation
    }
    
    // fun fact, focusedWindow need not return "AXWindow"...
    private func focusedWindow(app: NSRunningApplication) -> Element? {
        let axAppOptional = Application.init(app)
        guard let axApp = axAppOptional else { return nil }
        
        let axWindowOptional: UIElement? = try? axApp.attribute(.focusedWindow)
        guard let axWindow = axWindowOptional else { return nil }
        
        return Element.initialize(rawElement: axWindow.element)
    }
    
    private func activeScreenFrame(focusedWindowFrame: NSRect) -> NSRect {
        // When the focused window is in full screen mode in a secondary display,
        // NSScreen.main will point to the primary display.
        // this is a workaround.
        var activeScreen = NSScreen.main!
        var maxArea: CGFloat = 0
        for screen in NSScreen.screens {
            let intersection = screen.frame.intersection(focusedWindowFrame)
            let area = intersection.width * intersection.height
            if area > maxArea {
                maxArea = area
                activeScreen = screen
            }
        }
        return activeScreen.frame
    }
}

extension UserDefaults
{
    @objc dynamic var ForceKeyboardLayout: String?
    {
        get {
            return string(forKey: Utils.forceKeyboardLayoutKey)
        }
        set {
            set(newValue, forKey: Utils.forceKeyboardLayoutKey)
        }
    }

}
