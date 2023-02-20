//
//  HintModeQueryService.swift
//  Vimac
//
//  Created by Dexter Leng on 24/2/21.
//  Copyright © 2021 Dexter Leng. All rights reserved.
//

import Cocoa
import RxSwift
import AXSwift

class HintModeQueryService {
    let app: NSRunningApplication?
    let window: Element?
    let menu: Element?
    let hintCharacters: String
    
    init(app: NSRunningApplication?, window: Element?, menu: Element?, hintCharacters: String) {
        self.app = app
        self.window = window
        self.menu = menu
        self.hintCharacters = hintCharacters
    }
    
    func perform() -> Observable<Hint> {
        let elements = elementObservable().share()
        let count = elements.toArray().map({ $0.count })
        let hintStrings: Observable<String> = count
            .map { AlphabetHints().hintStrings(linkCount: $0, hintCharacters: self.hintCharacters) }
            .asObservable()
            .flatMap({ Observable.from($0) })
        
        let hints = Observable.zip(elements, hintStrings).map { Hint(element: $0, text: $1) }
        return hints
    }
    
    private func elementObservable() -> Observable<Element> {
        let nothing: Observable<Element> = Observable.empty()
        
        var menuBarElements = nothing
        if let app = app {
            menuBarElements = Utils.singleToObservable(single: queryMenuBarSingle(app: app))
        }
        
        if let menu = menu {
            return Utils.eagerConcat(observables: [
                menuBarElements,
                Utils.singleToObservable(single: queryMenuBarExtrasSingle()),
                Utils.singleToObservable(single: queryNotificationCenterSingle()),
                Utils.singleToObservable(single: queryOpenedMenuSingle(menu: menu))
            ])
        }
        
        var windowElements = nothing
        if let app = app,
           let window = window {
            windowElements = Utils.singleToObservable(single: queryWindowElementsSingle(app: app, window: window))
        }
        
        return Utils.eagerConcat(observables: [
            menuBarElements,
            Utils.singleToObservable(single: queryMenuBarExtrasSingle()),
            Utils.singleToObservable(single: queryNotificationCenterSingle()),
            windowElements
        ])
    }
    
    private func queryWindowElementsSingle(app: NSRunningApplication, window: Element) -> Single<[Element]> {
        return Single.create(subscribe: { event in
            let thread = Thread.init(block: {
                let service = QueryWindowService.init(app: app, window: window)
                let elements = try? service.perform()
                event(.success(elements ?? []))
            })
            thread.start()
            return Disposables.create {
                thread.cancel()
            }
        })
    }
    
    private func queryOpenedMenuSingle(menu: Element) -> Single<[Element]> {
        return Single.create(subscribe: { event in
            let thread = Thread.init(block: {
                print(menu.role)
                let menuItemsOptional: [AXUIElement]? = try? UIElement(menu.rawElement).attribute(.children)
                print(menuItemsOptional?.count)
                let menuItems = menuItemsOptional ?? []
                let menuItemElements = menuItems
                    .map { Element.initialize(rawElement: $0) }
                    .compactMap({ $0 })
                print(menuItemElements)
                event(.success(menuItemElements))
            })
            thread.start()
            return Disposables.create {
                thread.cancel()
            }
        })
    }
    
    private func queryMenuBarSingle(app: NSRunningApplication) -> Single<[Element]> {
        return Single.create(subscribe: { event in
            let thread = Thread.init(block: {                
                let service = QueryMenuBarItemsService.init(app: app)
                let elements = try? service.perform()
                event(.success(elements ?? []))
            })
            thread.start()
            return Disposables.create {
                thread.cancel()
            }
        })
    }
    
    private func queryMenuBarExtrasSingle() -> Single<[Element]> {
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
    
    private func queryNotificationCenterSingle() -> Single<[Element]> {
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
}
