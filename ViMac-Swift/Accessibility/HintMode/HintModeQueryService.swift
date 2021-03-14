//
//  HintModeQueryService.swift
//  Vimac
//
//  Created by Dexter Leng on 24/2/21.
//  Copyright © 2021 Dexter Leng. All rights reserved.
//

import Cocoa
import RxSwift

class HintModeQueryService {
    let app: NSRunningApplication
    let window: Element
    let hintCharacters: String
    
    init(app: NSRunningApplication, window: Element, hintCharacters: String) {
        self.app = app
        self.window = window
        self.hintCharacters = hintCharacters
    }
    
    func perform() -> Observable<Hint> {
        let elements = elementObservable()
        let count = elements.toArray().map({ $0.count })
        let hintStrings: Observable<String> = count
            .map { AlphabetHints().hintStrings(linkCount: $0, hintCharacters: self.hintCharacters) }
            .asObservable()
            .flatMap({ Observable.from($0) })
        
        let hints = Observable.zip(elements, hintStrings).map { Hint(element: $0, text: $1) }
        return hints
    }
    
    private func elementObservable() -> Observable<Element> {
        return Utils.eagerConcat(observables: [
            Utils.singleToObservable(single: queryMenuBarSingle()),
            Utils.singleToObservable(single: queryMenuBarExtrasSingle()),
            Utils.singleToObservable(single: queryNotificationCenterSingle()),
            Utils.singleToObservable(single: queryWindowElementsSingle()),
            Utils.singleToObservable(single: dockElements())
        ])
    }
    
    private func queryWindowElementsSingle() -> Single<[Element]> {
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
    
    private func queryMenuBarSingle() -> Single<[Element]> {
        return Single.create(subscribe: { [weak self] event in
            guard let self = self else {
                event(.success([]))
                return Disposables.create()
            }
            
            let thread = Thread.init(block: {                
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
    
    private func dockElements() -> Single<[Element]> {
        return Single.create(subscribe: { event in
            let thread = Thread.init(block: {
                let service = QueryDockService.init()
                let elements = service.perform()
                event(.success(elements ?? []))
            })
            thread.start()
            return Disposables.create {
                thread.cancel()
            }
        })
    }
}
