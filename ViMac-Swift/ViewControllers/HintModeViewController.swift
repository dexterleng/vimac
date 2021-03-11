//
//  HintModeViewController.swift
//  Vimac
//
//  Created by Dexter Leng on 9/10/19.
//  Copyright © 2019 Dexter Leng. All rights reserved.
//

import Cocoa
import AXSwift
import RxSwift
import Carbon.HIToolbox
import os
import Segment

struct Hint {
    let element: Element
    let text: String
}

enum HintAction {
    case leftClick
    case rightClick
    case doubleLeftClick
}

class HintModeViewController: ModeViewController, NSTextFieldDelegate {
    let app: NSRunningApplication
    let window: Element
    
    var hints: [Hint]?
    var hintsViewController: HintsViewController?
    
    let inputListener = HintModeInputListener()
    
    var characterStack: [Character] = [Character]()
    let startTime = CFAbsoluteTimeGetCurrent()
    
    // preferences
    let possibleHintCharacters = UserPreferences.HintMode.CustomCharactersProperty.read()
    let textSize = UserPreferences.HintMode.TextSizeProperty.readAsFloat()
    
    let disposeBag = DisposeBag()
    
    init(app: NSRunningApplication, window: Element) {
        self.app = app
        self.window = window
        super.init()
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        observeLetterKeyDown()
        observeEscKey()
        observeDeleteKey()
        observeSpaceKey()
        
        hideMouse()

        HintModeQueryService.init(app: app, window: window, hintCharacters: possibleHintCharacters).perform()
            .toArray()
            .observeOn(MainScheduler.instance)
            .do(onSuccess: { _ in self.logQueryTime() })
            .do(onError: { e in self.logError(e) })
            .subscribe(
                onSuccess: { self.onHintQueryCompleted(hints: $0) },
                onError: { _ in self.modeCoordinator?.exitMode()}
            )
            .disposed(by: disposeBag)
    }
    
    func logQueryTime() {
        let timeElapsed = CFAbsoluteTimeGetCurrent() - self.startTime
        os_log("[Hint mode] query time: %@", log: Log.accessibility, String(describing: timeElapsed))
    }
    
    func logError(_ e: Error) {
        os_log("[Hint mode] query error: %@", log: Log.accessibility, String(describing: e))
    }

    func onLetterKeyDown(event: NSEvent) {
        guard let character = event.charactersIgnoringModifiers?.first else { return }
        guard let hints = hints else { return }
        
        self.characterStack.append(character)
        let typed = String(self.characterStack)

        let matchingHints = hints.filter { $0.text.starts(with: typed.uppercased()) }
    
        if matchingHints.count == 0 && typed.count > 0 {
            Analytics.shared().track("Hint Mode Deadend")
            self.modeCoordinator?.exitMode()
            return
        }

        if matchingHints.count == 1 {
            Analytics.shared().track("Hint Mode Action Performed")
            
            let hint = matchingHints.first!
            
            // close the window before performing click(s)
            // Chrome's bookmark bar doesn't let you right click if Chrome is not the active window
            self.modeCoordinator?.exitMode()

            let originalMousePosition: NSPoint = {
                let invertedPos = NSEvent.mouseLocation
                let frame = GeometryUtils.convertAXFrameToGlobal(
                    NSRect(
                        origin: invertedPos,
                        size: NSSize.zero
                    )
                )
                return frame.origin
            }()
            let action: HintAction = {
                if (event.modifierFlags.rawValue & NSEvent.ModifierFlags.shift.rawValue == NSEvent.ModifierFlags.shift.rawValue) {
                    return .rightClick
                } else if (event.modifierFlags.rawValue & NSEvent.ModifierFlags.command.rawValue == NSEvent.ModifierFlags.command.rawValue) {
                    return .doubleLeftClick
                } else {
                    return .leftClick
                }
            }()
            performHintAction(hint, action: action)
            
            Utils.moveMouse(position: originalMousePosition)
        }

        // update hints to reflect new typed text
        self.updateHints(typed: typed)
    }
    
    func performHintAction(_ hint: Hint, action: HintAction) {
        let element = hint.element

        let frame = element.clippedFrame ?? element.frame
        let position = frame.origin
        let size = frame.size

        let centerPositionX = position.x + (size.width / 2)
        let centerPositionY = position.y + (size.height / 2)
        let centerPosition = NSPoint(x: centerPositionX, y: centerPositionY)

        Utils.moveMouse(position: centerPosition)
        
        switch action {
        case .leftClick:
            Utils.leftClickMouse(position: centerPosition)
        case .rightClick:
            Utils.rightClickMouse(position: centerPosition)
        case .doubleLeftClick:
            Utils.doubleLeftClickMouse(position: centerPosition)
        }
    }
    
    func observeLetterKeyDown() {
        inputListener.observeKeyDown(onEvent: { [weak self] event in
            self?.onLetterKeyDown(event: event)
        })
    }
    
    func observeEscKey() {
        inputListener.observeEscapeKey(onEvent: { [weak self] _ in
            Analytics.shared().track("Hint Mode Deactivated")
            self?.onEscape()
        })
    }
    
    func observeDeleteKey() {
        inputListener.observeDeleteKey(onEvent: { [weak self] _ in
            guard let vc = self else {
                return
            }
            _ = vc.characterStack.popLast()
            vc.updateHints(typed: String(vc.characterStack))
        })
    }
    
    func observeSpaceKey() {
        inputListener.observeSpaceKey(onEvent: { [weak self] _ in
            Analytics.shared().track("Hint Mode Rotated Hints")
            self?.rotateHints()
        })
    }
    
    func onHintQueryCompleted(hints: [Hint]) {
        self.hints = hints

        self.hintsViewController = HintsViewController(hints: self.hints!, textSize: CGFloat(textSize), hintCharacters: possibleHintCharacters)
        self.addChild(hintsViewController!)
        hintsViewController!.view.frame = self.view.frame
        self.view.addSubview(hintsViewController!.view)
    }

    private func removeChildViewController(_ vc: NSViewController) {
        if !self.children.contains(vc) {
            return
        }
        
        vc.view.removeFromSuperview()
        vc.removeFromParent()
    }
    
    func updateHints(typed: String) {
        guard let hintsVC = hintsViewController else { return }
        hintsVC.updateTyped(typed: typed)
    }
    
    func rotateHints() {
        guard let hintsVC = hintsViewController else { return }
        hintsVC.rotateHints()
    }
    
    func hideMouse() {
        HideCursorGlobally.hide()
    }
    
    func showMouse() {
        HideCursorGlobally.unhide()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        
        showMouse()
    }
}
