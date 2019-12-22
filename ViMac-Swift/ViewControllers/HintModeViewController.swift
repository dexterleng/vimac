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

class HintModeViewController: ModeViewController, NSTextFieldDelegate {
    let elements: Observable<UIElement>
    let textField = OverlayTextField(frame: NSRect(x: 0, y: 0, width: 0, height: 0))
    var hintViews: [HintView]?
    let compositeDisposable = CompositeDisposable()
    var characterStack: [Character] = [Character]()
    let elementFilters: [ElementFilter.Type] = [NoFilter.self, HasActionsFilter.self]

    init(elements: Observable<UIElement>) {
        self.elements = elements.share()
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        textField.stringValue = ""
        textField.isEditable = true
        textField.delegate = self
        // for some reason setting the text field to hidden breaks hint updating after the first hint update.
        // selectorTextField.isHidden = true
        textField.overlayTextFieldDelegate = self
        self.view.addSubview(textField)
        
        let escapeKeyDownObservable = textField.distinctNSEventObservable.filter({ event in
            return event.keyCode == kVK_Escape && event.type == .keyDown
        })
        
        let deleteKeyDownObservable = textField.distinctNSEventObservable.filter({ event in
            return event.keyCode == kVK_Delete && event.type == .keyDown
        })
        
        let spaceKeyDownObservable = textField.distinctNSEventObservable.filter({ event in
            return event.keyCode == kVK_Space && event.type == .keyDown
        })
        
        let tabKeyDownObservable = textField.distinctNSEventObservable.filter({ event in
            return event.keyCode == kVK_Tab && event.type == .keyDown
        }).share()
        
        let alphabetKeyDownObservable = textField.distinctNSEventObservable
            .filter({ event in
                guard let character = event.charactersIgnoringModifiers?.first else {
                    return false
                }
                return character.isLetter && event.type == .keyDown
            })
        
        self.compositeDisposable.insert(
            alphabetKeyDownObservable
                .observeOn(MainScheduler.instance)
                .subscribe(onNext: { [weak self] event in
                    guard let vc = self,
                        let character = event.charactersIgnoringModifiers?.first else {
                        return
                    }

                    vc.characterStack.append(character)
                    let typed = String(vc.characterStack)
            
                    let matchingHints = vc.hintViews!.filter { hintView in
                        return hintView.stringValue.starts(with: typed.uppercased())
                    }

                    if matchingHints.count == 0 && typed.count > 0 {
                        vc.modeCoordinator?.exitMode()
                        return
                    }
            
                    if matchingHints.count == 1 {
                        let matchingHint = matchingHints.first!
                        let buttonOptional = matchingHint.associatedElement
                        guard let button = buttonOptional else {
                            vc.modeCoordinator?.exitMode()
                            return
                        }
            
                        let buttonPositionOptional: NSPoint? = try? button.attribute(.position)
                        let buttonSizeOptional: NSSize? = try? button.attribute(.size)
            
                        guard let buttonPosition = buttonPositionOptional,
                            let buttonSize = buttonSizeOptional else {
                                vc.modeCoordinator?.exitMode()
                                return
                        }
            
                        let centerPositionX = buttonPosition.x + (buttonSize.width / 2)
                        let centerPositionY = buttonPosition.y + (buttonSize.height / 2)
                        let centerPosition = NSPoint(x: centerPositionX, y: centerPositionY)
            
                        // close the window before performing click(s)
                        // Chrome's bookmark bar doesn't let you right click if Chrome is not the active window
                        vc.modeCoordinator?.exitMode()
                        
                        Utils.moveMouse(position: centerPosition)
                        
                        if (event.modifierFlags.rawValue & NSEvent.ModifierFlags.shift.rawValue == NSEvent.ModifierFlags.shift.rawValue) {
                            Utils.rightClickMouse(position: centerPosition)
                        } else if (event.modifierFlags.rawValue & NSEvent.ModifierFlags.command.rawValue == NSEvent.ModifierFlags.command.rawValue) {
                            Utils.doubleLeftClickMouse(position: centerPosition)
                        } else if (event.modifierFlags.rawValue & NSEvent.ModifierFlags.control.rawValue == NSEvent.ModifierFlags.control.rawValue) {
                        } else {
                            Utils.leftClickMouse(position: centerPosition)
                        }
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
            deleteKeyDownObservable
                .observeOn(MainScheduler.instance)
                .subscribe(onNext: { [weak self] _ in
                    guard let vc = self else {
                        return
                    }
                    vc.characterStack.popLast()
                    vc.updateHints(typed: String(vc.characterStack))
        }))
        
        self.compositeDisposable.insert(
            spaceKeyDownObservable
                .observeOn(MainScheduler.instance)
                .subscribe(onNext: { [weak self] _ in
                    guard let vc = self else {
                        return
                    }
                    vc.rotateHints()
        }))

        self.compositeDisposable.insert(
            tabKeyDownObservable.enumerated()
                .withLatestFrom(elements.toArray(), resultSelector: { (a, elements) in
                    return (a.index + 1, elements)
                })
                .subscribe(onNext: { [weak self] (tabCount, elements) in
                    guard let vc = self else {
                        return
                    }
                    // cycle through the filters
                    let filter = vc.elementFilters[tabCount % vc.elementFilters.count]
                    let filteredElements = elements.filter({ filter.filterPredicate(element: $0) })
                    let hintStrings = AlphabetHints().hintStrings(linkCount: filteredElements.count)
                    let hintViews: [HintView] = filteredElements
                        .enumerated()
                        .map ({ (index, button) in
                            let positionFlippedOptional: NSPoint? = try? button.attribute(.position)

                            if let positionFlipped = positionFlippedOptional {
                                let text = HintView(frame: NSRect(x: 0, y: 0, width: 0, height: 0))
                                text.initializeHint(hintText: hintStrings[index], typed: "")
                                let positionRelativeToScreen = Utils.toOrigin(point: positionFlipped, size: text.frame.size)
                                let positionRelativeToWindow = vc.modeCoordinator!.windowController.window!.convertPoint(fromScreen: positionRelativeToScreen)
                                text.associatedElement = button
                                text.frame.origin = positionRelativeToWindow
                                return text
                            }
                            return nil })
                        .compactMap({ $0 })

                    
                    for existingHintView in vc.hintViews ?? [] {
                        existingHintView.removeFromSuperview()
                    }
                    
                    vc.hintViews = hintViews
                    for hintView in hintViews {
                        vc.view.addSubview(hintView)
                    }
                    
                    vc.characterStack.removeAll()
            })
        )
        
        
        self.compositeDisposable.insert(
            elements.toArray()
                .observeOn(MainScheduler.instance)
                .subscribe(
                onSuccess: { elements in
                    let hintStrings = AlphabetHints().hintStrings(linkCount: elements.count)

                    let hintViews: [HintView] = elements
                        .enumerated()
                        .map ({ (index, button) in
                            let text = HintView(frame: NSRect(x: 0, y: 0, width: 0, height: 0))
                            text.initializeHint(hintText: hintStrings[index], typed: "")
                            
                            let centerPositionOptional: NSPoint? = {
                                do {
                                    guard let topLeftPositionFlipped: NSPoint = try button.attribute(.position),
                                        let buttonSize: NSSize = try button.attribute(.size) else {
                                        return nil
                                    }
                                    let topLeftPositionRelativeToScreen = Utils.toOrigin(point: topLeftPositionFlipped, size: text.frame.size)
                                    guard let topLeftPositionRelativeToWindow = self.modeCoordinator?.windowController.window?.convertPoint(fromScreen: topLeftPositionRelativeToScreen) else {
                                        return nil
                                    }
                                    let x = (topLeftPositionRelativeToWindow.x + (buttonSize.width / 2)) - (text.frame.size.width / 2)
                                    let y = (topLeftPositionRelativeToWindow.y - (buttonSize.height) / 2) + (text.frame.size.height / 2)
                                    return NSPoint(x: x, y: y)
                                } catch {
                                    return nil
                                }
                            }()

                            guard let centerPosition = centerPositionOptional else {
                                return nil
                            }

                            text.associatedElement = button
                            text.frame.origin = centerPosition
                            return text
                        })
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
        for hintView in shuffledHintViews {
            self.view.addSubview(hintView)
        }
        self.hintViews = shuffledHintViews
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        self.compositeDisposable.dispose()
    }
}
