//
//  CursorModeViewController.swift
//  Vimac
//
//  Created by Huawei Matebook X Pro on 9/10/19.
//  Copyright © 2019 Dexter Leng. All rights reserved.
//

import Cocoa
import AXSwift
import RxSwift

class CursorModeViewController: ModeViewController, NSTextFieldDelegate {
    var cursorAction: CursorAction?
    var cursorSelector: CursorSelector?
    var allowedRoles: [Role]?
    var elements: Observable<UIElement>?
    let textField = CursorActionSelectorTextField(frame: NSRect(x: 0, y: 0, width: 0, height: 0))
    var hintViews: [HintView]?
    let compositeDisposable = CompositeDisposable()
    var characterStack: [Character] = [Character]()
    

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let cursorAction = self.cursorAction,
            let cursorSelector = self.cursorSelector,
            let allowedRoles = self.allowedRoles,
            let elements = self.elements else {
                self.modeCoordinator?.exitMode()
                return
        }

        textField.stringValue = ""
        textField.isEditable = true
        textField.delegate = self
        // for some reason setting the text field to hidden breaks hint updating after the first hint update.
        // selectorTextField.isHidden = true
        textField.overlayTextFieldDelegate = self
        self.view.addSubview(textField)
        
        let keyActionObservable = textField.nsEventObservable!
            .flatMapLatest({ event -> Observable<KeyAction> in
                let characterOptional: Character? = event.charactersIgnoringModifiers?.first
                
                var keyPositionOptional: KeyPosition? = nil
                switch (event.type) {
                case .keyDown:
                    keyPositionOptional = .keyDown
                case .keyUp:
                    keyPositionOptional = .keyUp
                default:
                    break
                }

                guard let character = characterOptional,
                    let keyPosition = keyPositionOptional else {
                        return Observable.empty()
                }
                
                return Observable.just(
                    KeyAction(keyPosition: keyPosition, character: character, modiferFlags: event.modifierFlags)
                )
            })
            .distinctUntilChanged({ (k1, k2) -> Bool in
                return k1.keyPosition == k2.keyPosition && k1.character == k2.character
            })
            .share()
        
        let escapeKeyDownObservable = keyActionObservable.filter({ keyAction in
            return keyAction.character == "\u{1B}" && keyAction.keyPosition == .keyDown
        })
        
        let alphabetKeyDownObservable = keyActionObservable
            .filter({ keyAction in
                return keyAction.character.isLetter && keyAction.keyPosition == .keyDown
            })
        
        self.compositeDisposable.insert(
            alphabetKeyDownObservable
                .observeOn(MainScheduler.instance)
                .subscribe(onNext: { [weak self] keyAction in
                    guard let vc = self else {
                        return
                    }
                    vc.characterStack.append(keyAction.character)
                    let typed = String(vc.characterStack)
                    if let lastCharacter = typed.last {
                        if lastCharacter == " " {
                            vc.characterStack.popLast()
                            vc.rotateHints()
                            return
                        }
                    }
            
                    let matchingHints = vc.hintViews!.filter { hintView in
                        return hintView.stringValue.starts(with: typed.uppercased())
                    }
            
                    if matchingHints.count == 0 && typed.count > 0 {
                        vc.modeCoordinator?.exitMode()
                        return
                    }
            
                    if matchingHints.count == 1 {
                        let matchingHint = matchingHints.first!
                        let buttonOptional = matchingHint.associatedButton
                        guard let button = buttonOptional else {
                            vc.modeCoordinator?.exitMode()
                            return
                        }
            
                        var buttonPositionOptional: NSPoint?
                        var buttonSizeOptional: NSSize?
                        do {
                            buttonPositionOptional = try button.attribute(.position)
                            buttonSizeOptional = try button.attribute(.size)
                        } catch {
                            vc.modeCoordinator?.exitMode()
                            return
                        }
            
                        guard let buttonPosition = buttonPositionOptional,
                            let buttonSize = buttonSizeOptional else {
                                vc.modeCoordinator?.exitMode()
                                return
                        }
            
                        let centerPositionX = buttonPosition.x + (buttonSize.width / 2)
                        let centerPositionY = buttonPosition.y + (buttonSize.height / 2)
                        let centerPosition = NSPoint(x: centerPositionX, y: centerPositionY)
            
                        Utils.moveMouse(position: centerPosition)
                        var actionOptional: CursorAction? = nil

                        switch (keyAction.modiferFlags.rawValue) {
                            // no modifiers
                            case 256:
                                Utils.leftClickMouse(position: centerPosition)
                            // holding shift
                            case 131330:
                                Utils.rightClickMouse(position: centerPosition)
                            // holding option
                            case 524576:
                                break
                            // holding command
                            case 1048840:
                                Utils.doubleLeftClickMouse(position: centerPosition)
                            default:
                                break
                        }
                                        
            
                        vc.modeCoordinator?.exitMode()
                        return
                    }
            
                    // update hints to reflect new typed text
                    vc.updateHints(typed: typed)
                })
        )
        
        self.compositeDisposable.insert(
            escapeKeyDownObservable
                .observeOn(MainScheduler.instance)
                .subscribe(onNext: { [weak self] _ in
                    self?.onEscape()
        }))
        
        self.compositeDisposable.insert(
            elements.toArray()
                .observeOn(MainScheduler.instance)
                .subscribe(
                onSuccess: { elements in
                    let hintStrings = AlphabetHints().hintStrings(linkCount: elements.count)

                    let hintViews: [HintView] = elements
                        .enumerated()
                        .map ({ (index, button) in
                            let positionFlippedOptional: NSPoint? = {
                                do {
                                    return try button.attribute(.position)
                                } catch {
                                    return nil
                                }
                            }()

                            if let positionFlipped = positionFlippedOptional {
                                let text = HintView(frame: NSRect(x: 0, y: 0, width: 0, height: 0))
                                text.initializeHint(hintText: hintStrings[index], typed: "")
                                let positionRelativeToScreen = Utils.toOrigin(point: positionFlipped, size: text.frame.size)
                                let positionRelativeToWindow = self.modeCoordinator!.windowController.window!.convertPoint(fromScreen: positionRelativeToScreen)
                                text.associatedButton = button
                                text.frame.origin = positionRelativeToWindow
                                text.zIndex = index
                                return text
                            }
                            return nil })
                        .compactMap({ $0 })
                    
                    self.hintViews = hintViews

                    for hintView in hintViews {
                        self.view.addSubview(hintView)
                    }
                    self.textField.becomeFirstResponder()
                }, onError: { error in
                    print(error)
                })
        )
    }
    
    func updateHints(typed: String) {
        guard let hintViews = self.hintViews else {
            self.modeCoordinator?.exitMode()
            return
        }

        hintViews.forEach { hintView in
            hintView.isHidden = true
            if hintView.stringValue.starts(with: typed.uppercased()) {
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
        for (index, hintView) in shuffledHintViews.enumerated() {
            hintView.zIndex = index
            self.view.addSubview(hintView)
        }
        self.hintViews = shuffledHintViews
    }
    
//    func controlTextDidChange(_ obj: Notification) {
//        let typed = textField.stringValue
//        guard let cursorAction = self.cursorAction,
//            let cursorSelector = self.cursorSelector,
//            let allowedRoles = self.allowedRoles,
//            let hintViews = self.hintViews else {
//                self.modeCoordinator?.exitMode()
//                return
//        }
//
//        if let lastCharacter = typed.last {
//            if lastCharacter == " " {
//                textField.stringValue = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
//                self.rotateHints()
//                return
//            }
//        }
//
//        let matchingHints = hintViews.filter { hintView in
//            return hintView.stringValue.starts(with: typed.uppercased())
//        }
//
//        if matchingHints.count == 0 && typed.count > 0 {
//            self.modeCoordinator?.exitMode()
//            return
//        }
//
//        if matchingHints.count == 1 {
//            let matchingHint = matchingHints.first!
//            let buttonOptional = matchingHint.associatedButton
//            guard let button = buttonOptional else {
//                self.modeCoordinator?.exitMode()
//                return
//            }
//
//            var buttonPositionOptional: NSPoint?
//            var buttonSizeOptional: NSSize?
//            do {
//                buttonPositionOptional = try button.attribute(.position)
//                buttonSizeOptional = try button.attribute(.size)
//            } catch {
//                self.modeCoordinator?.exitMode()
//                return
//            }
//
//            guard let buttonPosition = buttonPositionOptional,
//                let buttonSize = buttonSizeOptional else {
//                    self.modeCoordinator?.exitMode()
//                    return
//            }
//
//            let centerPositionX = buttonPosition.x + (buttonSize.width / 2)
//            let centerPositionY = buttonPosition.y + (buttonSize.height / 2)
//            let centerPosition = NSPoint(x: centerPositionX, y: centerPositionY)
//
//            Utils.moveMouse(position: centerPosition)
//            if cursorAction == .leftClick {
//                Utils.leftClickMouse(position: centerPosition)
//            } else if cursorAction == .rightClick {
//                Utils.rightClickMouse(position: centerPosition)
//            } else if cursorAction == .doubleLeftClick {
//                Utils.doubleLeftClickMouse(position: centerPosition)
//            } else if cursorAction == .move {
//                Utils.moveMouse(position: centerPosition)
//            }
//
//            self.modeCoordinator?.exitMode()
//            return
//        }
//
//        // update hints to reflect new typed text
//        self.updateHints(typed: typed)
//    }
    
    override func viewDidDisappear() {
        super.viewDidDisappear()
        self.compositeDisposable.dispose()
    }
}
