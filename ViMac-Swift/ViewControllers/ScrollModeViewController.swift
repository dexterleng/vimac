//
//  ScrollModeViewController.swift
//  Vimac
//
//  Created by Dexter Leng on 9/10/19.
//  Copyright © 2019 Dexter Leng. All rights reserved.
//

import Cocoa
import RxSwift
import Carbon.HIToolbox
import AXSwift

class ScrollModeViewController: ModeViewController, NSTextFieldDelegate {
    let textField = OverlayTextField(frame: NSRect(x: 0, y: 0, width: 0, height: 0))
    let borderView = BorderView();
    var compositeDisposable: CompositeDisposable?
    var tabKeyDisposable: Disposable?
    var currentScrollAreaIndex = 0
    let scrollAreas = getScrollAreasByDescendingArea()

    static func getScrollAreasByDescendingArea() -> [CachedUIElement] {
        guard let applicationWindow = Utils.getCurrentApplicationWindowManually() else {
            return []
        }
        
        let cachedApplicationWindow = CachedUIElement.init(applicationWindow.element)
        
        var scrollAreas = [CachedUIElement]()
        func fn(element: CachedUIElement) -> Void {
            _ = try? element.getMultipleAttributes([.role, .position, .size, .children])

            let roleOptional: String? = try? element.attribute(.role);
            
            if let role = roleOptional {
                if role == Role.scrollArea.rawValue {
                    scrollAreas.append(element)
                    return
                }
            }

            let children = (try? element.attribute(Attribute.children) as [AXUIElement]?) ?? [];

            for child in children {
                fn(element: CachedUIElement(child))
            }
        }
        fn(element: cachedApplicationWindow)
        let scrollAreasDescendingArea = scrollAreas.sorted(by: { (scrollAreaA, scrollAreaB) in
            let sizeA: NSSize = (try? scrollAreaA.attribute(.size)) ?? .zero;
            let sizeB: NSSize = (try? scrollAreaB.attribute(.size)) ?? .zero;
            return (sizeA.width * sizeA.height) > (sizeB.width * sizeB.height)
        })
        return scrollAreasDescendingArea
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        textField.stringValue = ""
        textField.isEditable = true
        textField.delegate = self
        textField.overlayTextFieldDelegate = self
        self.view.addSubview(textField)
        self.view.addSubview(borderView)
        
        
        if self.scrollAreas.count == 0 {
            self.modeCoordinator?.exitMode()
            return
        }

        self.compositeDisposable = self.setActiveScrollArea(index: self.currentScrollAreaIndex)
        
        let tabKeyDownObservable = textField.distinctNSEventObservable.filter({ event in
            return event.keyCode == kVK_Tab && event.type == .keyDown
        })
        
        self.tabKeyDisposable = tabKeyDownObservable
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { [weak self] event in
                self?.compositeDisposable?.dispose()
                self?.compositeDisposable = self?.cycleActiveScrollArea()
            })
    }
    
    func cycleActiveScrollArea() -> CompositeDisposable? {
        self.currentScrollAreaIndex = (self.currentScrollAreaIndex + 1) % self.scrollAreas.count
        return self.setActiveScrollArea(index: self.currentScrollAreaIndex)
    }
    
    func setActiveScrollArea(index: Int) -> CompositeDisposable? {
        if index < 0 || index >= scrollAreas.count {
            return nil
        }
        let scrollArea = scrollAreas[index]
        let scrollAreaSizeOptional: NSSize? = try? scrollArea.attribute(.size)
        let scrollAreaPositionOptional: NSPoint? = try? scrollArea.attribute(.position)
        guard let scrollAreaSize = scrollAreaSizeOptional,
            let scrollAreaPosition = scrollAreaPositionOptional else {
            self.modeCoordinator?.exitMode()
            return nil
        }

        resizeBorderViewToFitScrollArea(scrollAreaSize: scrollAreaSize, scrollAreaPosition: scrollAreaPosition)
        moveMouseToScrollAreaBottomLeft(scrollAreaPosition: scrollAreaPosition, scrollAreaSize: scrollAreaSize)
        return setupScrollObservers(scrollAreaSize: scrollAreaSize, scrollAreaPosition: scrollAreaPosition)
    }
    
    func resizeBorderViewToFitScrollArea(scrollAreaSize: NSSize, scrollAreaPosition: NSPoint) {
        let topLeftPositionRelativeToScreen = Utils.toOrigin(point: scrollAreaPosition, size: scrollAreaSize)
        guard let topLeftPositionRelativeToWindow = self.modeCoordinator?.windowController.window?.convertPoint(fromScreen: topLeftPositionRelativeToScreen) else {
            return
        }
        self.borderView.frame = NSRect(origin: topLeftPositionRelativeToWindow, size: scrollAreaSize)
    }
    
    func setupScrollObservers(scrollAreaSize: NSSize, scrollAreaPosition: NSPoint) -> CompositeDisposable {
        let disposable = CompositeDisposable()
        
        let scrollSensitivity = UserDefaults.standard.integer(forKey: Utils.scrollSensitivityKey)
        let isVerticalScrollReversed = UserDefaults.standard.bool(forKey: Utils.isVerticalScrollReversedKey)
        let isHorizontalScrollReversed = UserDefaults.standard.bool(forKey: Utils.isHorizontalScrollReversedKey)
        let verticalScrollMultiplier = isVerticalScrollReversed ? -1 : 1
        let horizontalScrollMultiplier = isHorizontalScrollReversed ? -1 : 1
        
        let escapeKeyDownObservable = textField.distinctNSEventObservable.filter({ event in
            return event.keyCode == kVK_Escape && event.type == .keyDown
        });
        
        disposable.insert(
            escapeKeyDownObservable
                .observeOn(MainScheduler.instance)
                .subscribe(onNext: { [weak self] _ in
                    self?.onEscape()
        }))
        
        disposable.insert(
            AccessibilityObservables.scrollObservableSmooth(
                textField: textField,
                character: "j",
                yAxis: Int64(-1 * verticalScrollMultiplier * scrollSensitivity),
                xAxis: 0,
                frequencyMilliseconds: 20)
                .subscribe()
        )
        
        disposable.insert(
            AccessibilityObservables.scrollObservableSmooth(
                textField: textField,
                character: "k",
                yAxis: Int64(verticalScrollMultiplier * scrollSensitivity),
                xAxis: 0,
                frequencyMilliseconds: 20)
                .subscribe()
        )
        
        disposable.insert(
            AccessibilityObservables.scrollObservableSmooth(
                textField: textField,
                character: "h",
                yAxis: 0,
                xAxis: Int64(horizontalScrollMultiplier * scrollSensitivity),
                frequencyMilliseconds: 20)
                .subscribe()
        )
        
        disposable.insert(
            AccessibilityObservables.scrollObservableSmooth(
                textField: textField,
                character: "l",
                yAxis: 0,
                xAxis: Int64(-1 * horizontalScrollMultiplier * scrollSensitivity),
                frequencyMilliseconds: 20)
                .subscribe()
        )
        
        let halfScrollAreaHeight = Int(scrollAreaSize.height / 2)
        
        disposable.insert(
            AccessibilityObservables.scrollObservableChunky(
                textField: textField,
                character: "d",
                yAxis: Int32(verticalScrollMultiplier * -1 * halfScrollAreaHeight),
                xAxis: 0, frequencyMilliseconds: 200)
                .subscribe()
        )
        
        disposable.insert(
            AccessibilityObservables.scrollObservableChunky(
                textField: textField,
                character: "u",
                yAxis: Int32(verticalScrollMultiplier * halfScrollAreaHeight),
                xAxis: 0,
                frequencyMilliseconds: 200)
                .subscribe()
        )
        
        return disposable
    }
    
    func moveMouseToScrollAreaBottomLeft(scrollAreaPosition: NSPoint, scrollAreaSize: NSSize) {
        let positionX = scrollAreaPosition.x + 4
        let positionY = scrollAreaPosition.y + scrollAreaSize.height - 4
        let position = NSPoint(x: positionX, y: positionY)
        Utils.moveMouse(position: position)
    }
    
    override func viewDidDisappear() {
        self.tabKeyDisposable?.dispose()
        self.compositeDisposable?.dispose()
    }
}
