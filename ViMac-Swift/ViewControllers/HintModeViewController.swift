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

struct Hint {
    let element: Element
    let text: String
}

class HintModeViewController: ModeViewController, NSTextFieldDelegate {
    let app: NSRunningApplication
    let window: Element
    
    lazy var inputListeningTextField = instantiateInputListeningTextField()
    var hintViews: [HintView]?
    let inputListener = HintModeInputListener()
    
    var characterStack: [Character] = [Character]()
    let originalMousePosition = NSEvent.mouseLocation
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

        self.view.addSubview(inputListeningTextField)
        
        observeLetterKeyDown()
        observeEscKey()
        observeDeleteKey()
        observeSpaceKey()
        
        hideMouse()

        elementObservable().toArray()
            .observeOn(MainScheduler.instance)
            .subscribeOn(ConcurrentDispatchQueueScheduler.init(qos: .userInitiated, leeway: .nanoseconds(0)))
            .do(onSuccess: { _ in self.logQueryTime() })
            .do(onError: { e in self.logError(e) })
            .subscribe(
                onSuccess: { self.onElementTraversalComplete(elements: $0) },
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
    
    func elementObservable() -> Observable<Element> {
        return Utils.eagerConcat(observables: [
            Utils.singleToObservable(single: queryWindowElementsSingle()),
            Utils.singleToObservable(single: queryMenuBarSingle()),
            Utils.singleToObservable(single: queryMenuBarExtrasSingle()),
            Utils.singleToObservable(single: queryNotificationCenterSingle())
        ])
    }
    
    func queryWindowElementsSingle() -> Single<[Element]> {
        return Single.create(subscribe: { [weak self] event in
            guard let self = self else {
                event(.success([]))
                return Disposables.create()
            }
            
            let thread = Thread.init(block: {
                let service = QueryWindowService.init(app: self.app, window: self.window)
                let elements = try? service.perform()
                event(.success(elements ?? []))
            })
            thread.start()
            return Disposables.create {
                thread.cancel()
            }
        })
    }
    
    func queryMenuBarSingle() -> Single<[Element]> {
        return Single.create(subscribe: { [weak self] event in
            guard let self = self else {
                event(.success([]))
                return Disposables.create()
            }
            
            let thread = Thread.init(block: {
                // as of 28e46b9cbe9a38e7c43c1eb1f0d8953d99bc5ef9,
                // when one activates hint mode when the Vimac preference page is frontmost,
                // the app crashes with EXC_BAD_INSTRUCTION when retrieving menu bar items attributes through Element.initialize
                // I suspect that threading is the cause of crashing when reading attributes from your own app
                let isVimac = self.app.bundleIdentifier == Bundle.main.bundleIdentifier
                if isVimac {
                    event(.success([]))
                    return
                }
                
                let service = QueryMenuBarItemsService.init(app: self.app)
                let elements = try? service.perform()
                event(.success(elements ?? []))
            })
            thread.start()
            return Disposables.create {
                thread.cancel()
            }
        })
    }
    
    func queryMenuBarExtrasSingle() -> Single<[Element]> {
        return Single.create(subscribe: { event in
            let thread = Thread.init(block: {
                let service = QueryMenuBarExtrasService.init()
                let elements = try? service.perform()
                event(.success(elements ?? []))
            })
            thread.start()
            return Disposables.create {
                thread.cancel()
            }
        })
    }
    
    func queryNotificationCenterSingle() -> Single<[Element]> {
        return Single.create(subscribe: { event in
            let thread = Thread.init(block: {
                let service = QueryNotificationCenterItemsService.init()
                let elements = try? service.perform()
                event(.success(elements ?? []))
            })
            thread.start()
            return Disposables.create {
                thread.cancel()
            }
        })
    }
    
    func onLetterKeyDown(event: NSEvent) {
        guard let character = event.charactersIgnoringModifiers?.first else { return }
        guard let hintViews = self.hintViews else { return }

        self.characterStack.append(character)
        let typed = String(self.characterStack)

        let matchingHints = hintViews.filter { hintView in
            return hintView.hintTextView!.stringValue.starts(with: typed.uppercased())
        }

        if matchingHints.count == 0 && typed.count > 0 {
            self.modeCoordinator?.exitMode()
            return
        }

        if matchingHints.count == 1 {
            let matchingHint = matchingHints.first!
            let element = matchingHint.associatedElement

            let frame = element.clippedFrame ?? element.frame
            let position = frame.origin
            let size = frame.size

            let centerPositionX = position.x + (size.width / 2)
            let centerPositionY = position.y + (size.height / 2)
            let centerPosition = NSPoint(x: centerPositionX, y: centerPositionY)

            // close the window before performing click(s)
            // Chrome's bookmark bar doesn't let you right click if Chrome is not the active window
            self.modeCoordinator?.exitMode()
            
            Utils.moveMouse(position: centerPosition)
            
            if (event.modifierFlags.rawValue & NSEvent.ModifierFlags.shift.rawValue == NSEvent.ModifierFlags.shift.rawValue) {
                Utils.rightClickMouse(position: centerPosition)
            } else if (event.modifierFlags.rawValue & NSEvent.ModifierFlags.command.rawValue == NSEvent.ModifierFlags.command.rawValue) {
                Utils.doubleLeftClickMouse(position: centerPosition)
            } else if (event.modifierFlags.rawValue & NSEvent.ModifierFlags.control.rawValue == NSEvent.ModifierFlags.control.rawValue) {
            } else {
                Utils.leftClickMouse(position: centerPosition)
            }
            
            revertMouseLocation()
            return
        }

        // update hints to reflect new typed text
        self.updateHints(typed: typed)
    }
    
    func observeLetterKeyDown() {
        inputListener.observeKeyDown(onEvent: { [weak self] event in
            self?.onLetterKeyDown(event: event)
        })
    }
    
    func observeEscKey() {
        inputListener.observeEscapeKey(onEvent: { [weak self] _ in
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
            self?.rotateHints()
        })
    }
    
    func onElementTraversalComplete(elements: [Element]) {
        let hintStrings = AlphabetHints().hintStrings(linkCount: elements.count, hintCharacters: possibleHintCharacters)
        
        let hints = elements
            .enumerated()
            .map({ (i, e) in Hint(element: e, text: hintStrings[i]) })

        let hintViews: [HintView] = hints
            .map({ instantiateHintView(hint: $0, textSize: CGFloat(textSize)) })
            .compactMap({ $0 })
        
        self.hintViews = hintViews

        for hintView in hintViews {
            self.view.addSubview(hintView)
        }
        
        self.inputListeningTextField.becomeFirstResponder()
    }
    
    func instantiateHintView(hint: Hint, textSize: CGFloat) -> HintView? {
        let text = HintView(associatedElement: hint.element, hintTextSize: CGFloat(textSize), hintText: hint.text, typedHintText: "")
        
        let centerPositionOptional: NSPoint? = {
            do {
                let globalElementFrame = GeometryUtils.convertAXFrameToGlobal(hint.element.frame)
                let screenOrigin = self.view.window!.frame.origin
                let elementFrameRelativeToScreen = GeometryUtils.convertGlobalFrame(globalElementFrame, relativeTo: screenOrigin)
                let elementCenter: NSPoint = GeometryUtils.center(elementFrameRelativeToScreen)
                
                let hintOrigin = NSPoint(
                    x: elementCenter.x - (text.frame.size.width / 2),
                    y: elementCenter.y - (text.frame.size.height / 2)
                )

                if hintOrigin.x.isNaN || hintOrigin.y.isNaN {
                    return nil
                }
                
                return hintOrigin
            } 
        }()

        guard let centerPosition = centerPositionOptional else {
            return nil
        }
        text.frame.origin = centerPosition
        
        return text
    }
    
    func updateHints(typed: String) {
        guard let hintViews = self.hintViews else {
            self.modeCoordinator?.exitMode()
            return
        }

        hintViews.forEach { hintView in
            hintView.isHidden = true
            if hintView.hintTextView!.stringValue.starts(with: typed.uppercased()) {
                hintView.updateTypedText(typed: typed)
                hintView.isHidden = false
            }
        }
    }
    
    // randomly rotate hints
    // ideally we group them into clusters of intersecting hints and rotate within those clusters
    // but this is just a quick fast hack
    func rotateHints() {
        guard let hintViews = self.hintViews else {
            self.modeCoordinator?.exitMode()
            return
        }
        
        for hintView in hintViews {
            hintView.removeFromSuperview()
        }
        
        let shuffledHintViews = hintViews.shuffled()
        for hintView in shuffledHintViews {
            self.view.addSubview(hintView)
        }
        self.hintViews = shuffledHintViews
    }
    
    func hideMouse() {
        HideCursorGlobally.hide()
    }
    
    func showMouse() {
        HideCursorGlobally.unhide()
    }
    
    private func revertMouseLocation() {
        let frame = GeometryUtils.convertAXFrameToGlobal(
            NSRect(
                origin: originalMousePosition,
                size: NSSize.zero
            )
        )
        Utils.moveMouse(position: frame.origin)
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        
        showMouse()
    }
    
    func instantiateInputListeningTextField() -> NSTextField {
        let textField = NSTextField()
        textField.stringValue = ""
        textField.isEditable = true
        return textField
    }
}
