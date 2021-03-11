//
//  ScrollModeActiveViewController.swift
//  Vimac
//
//  Created by Dexter Leng on 15/11/20.
//  Copyright © 2020 Dexter Leng. All rights reserved.
//

import Cocoa
import RxSwift
import Segment

class ScrollModeActiveViewController: NSViewController {
    private let scrollAreas: [Element]
    private var activeScrollAreaIndex: Int = 0
    private let inputListener: InputListener
    private let disposeBag = DisposeBag()
    private let originalMousePosition = NSEvent.mouseLocation
    
    init(scrollAreas: [Element], inputListener: InputListener) {
        assert(scrollAreas.count > 0)

        self.scrollAreas = scrollAreas
        self.inputListener = inputListener
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }
    
    override func loadView() {
        self.view = NSView()
    }
    
    override func viewDidAppear() {
        setActiveScrollArea(0)
        observeTabKey().disposed(by: disposeBag)
        HideCursorGlobally.hide()
    }
    
    override func viewDidDisappear() {
        revertMouseLocation()
        HideCursorGlobally.unhide()
    }
    
    private func observeTabKey() -> Disposable {
        let tabEvents = inputListener.keyDownEvents.filter { $0.keyCode == kVK_Tab }
        return tabEvents
            .bind(onNext: { [weak self] _ in
                self?.activateNextScrollArea()
            })
    }
    
    private func activateNextScrollArea() {
        Analytics.shared().track("Scroll Mode Cycle Scroll Area")
        
        activeScrollAreaIndex = (activeScrollAreaIndex + 1) % scrollAreas.count
        setActiveScrollArea(activeScrollAreaIndex)
    }
    
    private func setActiveScrollArea(_ index: Int) {
        let scrollArea = scrollAreas[index]
        self.activeScrollAreaIndex = index
        
        setActiveScrollAreaVC(scrollArea)
    }
    
    private func setActiveScrollAreaVC(_ scrollArea: Element) {
        let frame: NSRect = {
            let frameRelativeToScreen = GeometryUtils.convertAXFrameToGlobal(scrollArea.frame)
            return self.view.window!.convertFromScreen(frameRelativeToScreen)
        }()
        let vc = ScrollModeActiveScrollAreaViewController(scrollArea: scrollArea, inputListener: inputListener)
        vc.view.frame = frame
        setChildViewController(vc)
    }
    
    private func setChildViewController(_ vc: NSViewController) {
        assert(self.children.count <= 1)
        removeChildViewController()
        
        self.addChild(vc)
        self.view.addSubview(vc.view)
    }
    
    private func removeChildViewController() {
        guard let childVC = self.children.first else { return }
        childVC.view.removeFromSuperview()
        childVC.removeFromParent()
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
}
