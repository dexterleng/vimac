//
//  NewScrollModeViewController.swift
//  Vimac
//
//  Created by Dexter Leng on 14/11/20.
//  Copyright © 2020 Dexter Leng. All rights reserved.
//

import Cocoa
import RxSwift
import Segment

class ScrollModeViewController: ModeViewController {
    private let disposeBag = DisposeBag()
    private let inputListener = InputListener()
    private let window: Element

    init(window: Element) {
        self.window = window
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override func viewWillAppear() {
        observeScrollAreas().disposed(by: disposeBag)
        observeEscKey().disposed(by: disposeBag)
    }

    private func setActiveState(scrollAreas: [Element]) {
        let vc = ScrollModeActiveViewController(scrollAreas: scrollAreas, inputListener: inputListener)
        setChildViewController(vc)
    }

    private func setChildViewController(_ vc: NSViewController) {
        assert(self.children.count <= 1)
        removeChildViewController()

        self.addChild(vc)
        vc.view.frame = self.view.frame
        self.view.addSubview(vc.view)
    }

    private func removeChildViewController() {
        guard let childVC = self.children.first else { return }
        childVC.view.removeFromSuperview()
        childVC.removeFromParent()
    }

    private func observeScrollAreas() -> Disposable {
        fetchScrollAreas()
            .observeOn(MainScheduler.instance)
            .subscribe(onSuccess: { [weak self] scrollAreas in
                self?.setActiveState(scrollAreas: scrollAreas)
            }, onError: { [weak self] _ in
                self?.modeCoordinator?.exitMode()
            })
    }

    private func observeEscKey() -> Disposable {
        let escEvents = inputListener.keyDownEvents.filter { $0.keyCode == kVK_Escape }
        return escEvents
            .bind(onNext: { [weak self] _ in
                Analytics.shared().track("Scroll Mode Exited")
                self?.modeCoordinator?.exitMode()
            })
    }

    private func fetchScrollAreas() -> Single<[Element]> {
        return Single.create { observer in
            let thread = Thread.init {
                do {
                    var scrollAreas = try QueryScrollAreasService.init(windowElement: self.window).perform()

                    scrollAreas.append(self.window)

                    observer(.success(scrollAreas))
                } catch {
                    observer(.error(error))
                }
            }
            thread.start()
            return Disposables.create {
                thread.cancel()
            }
        }
    }
}
