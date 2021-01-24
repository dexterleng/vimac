//
//  ListenForKeySequence.swift
//  Vimac
//
//  Created by Dexter Leng on 1/1/21.
//  Copyright © 2021 Dexter Leng. All rights reserved.
//

import Cocoa
import RxRelay

class KeySequenceListener {
    let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
    var eventTap: GlobalEventTap?
    private let inputState = InputState()
    private var typed: [CGEvent] = []
    private var sequences: [[Character]] = []
    private var timer: Timer?
    private let resetDelay: TimeInterval
    
    private let matchRelay: PublishRelay<([Character])> = .init()
    lazy var matchEvents = matchRelay.asObservable()
    
    init(resetDelay: TimeInterval = 0.25) {
        self.resetDelay = resetDelay
    }

    func registerSequence(seq: [Character]) throws -> Bool {
        let success = try inputState.addWord(seq)
        if !success {
            return false
        }
        sequences.append(seq)
        return true
    }
    
    func started() -> Bool {
        guard let eventTap = eventTap else { return false }
        return eventTap.enabled()
    }
    
    func start() {
        if eventTap == nil {
            eventTap = GlobalEventTap(eventMask: mask, onEvent: { [weak self] event -> CGEvent? in
                guard let self = self else { return event}
                return self.onEvent(event: event)
            })
        }
        
        eventTap?.enable()
    }
    
    func stop() {
        eventTap?.disable()
        eventTap = nil
    }
    
    private func onEvent(event: CGEvent) -> CGEvent? {
        guard let nsEvent = NSEvent(cgEvent: event) else {
            resetInput()
            return event
        }
        
        let modifiersPresent = nsEvent.modifierFlags.rawValue != 256
        if modifiersPresent {
            resetInput()
            return event
        }

        guard let c = nsEvent.characters?.first else {
            resetInput()
            return event
        }
        
        if nsEvent.isARepeat {
            resetInput()
            return event
        }

        typed.append(event)
        try! inputState.advance(c)

        if inputState.state == .advancable {
            setTimeout()
            return nil
        } else if inputState.state == .matched {
            onMatch()
            resetInput()
            return nil
        } else if inputState.state == .deadend {
            // returning the event to the tap should be faster than emitting it.
            if typed.count == 1 {
                let e = typed.first!
                resetInput()
                return e
            }
            emitTyped()
            resetInput()
            return nil
        } else {
            fatalError()
        }
    }
    
    private func onMatch() {
        let sequence = try! inputState.matchedWord()
        matchRelay.accept(sequence)
    }
    
    private func emitTyped() {
        for keyDownEvent in typed {
            keyDownEvent.post(tap: .cghidEventTap)
            
            let keyUpEvent = keyDownEvent.copy()!
            keyUpEvent.type = .keyUp
            keyUpEvent.post(tap: .cghidEventTap)
        }
    }
    
    private func resetInput() {
        typed = []
        inputState.resetInput()
        timer?.invalidate()
    }
    
    @objc private func onTimeout() {
        emitTyped()
        resetInput()
    }
    
    private func setTimeout() {
        self.timer = Timer.scheduledTimer(timeInterval: resetDelay, target: self, selector: #selector(onTimeout), userInfo: nil, repeats: false)
    }
}
