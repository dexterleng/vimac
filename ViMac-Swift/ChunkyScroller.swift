//
//  ChunkyScroller.swift
//  Vimac
//
//  Created by Dexter Leng on 14/6/20.
//  Copyright © 2020 Dexter Leng. All rights reserved.
//

import Cocoa

class ChunkyScroller: Scroller {
    static func instantiate(direction: ScrollDirection, scrollAmount: Int) -> ChunkyScroller {
        var xAxis = Int32(0)
        var yAxis = Int32(0)
        
        switch direction {
            case .halfLeft:
                xAxis = Int32(scrollAmount)
            case .halfRight:
                xAxis = Int32(-scrollAmount)
            case .halfDown:
                yAxis = Int32(-scrollAmount)
            case .halfUp:
                yAxis = Int32(scrollAmount)
            default:
                fatalError("<direction> scroll directions should not used for SmoothScroller")
        }
        
        let isHorizontalScrollReversed = UserPreferences.ScrollMode.ReverseHorizontalScrollProperty.read()
        let isVerticalScrollReversed = UserPreferences.ScrollMode.ReverseVerticalScrollProperty.read()
        
        if isHorizontalScrollReversed {
            xAxis = -xAxis
        }
        
        if isVerticalScrollReversed {
            yAxis = -yAxis
        }
        
        let frequency = 0.25
        
        return ChunkyScroller.init(frequency: frequency, xAxis: xAxis, yAxis: yAxis)
    }
    
    static func instantiateForSmoothScroll(direction: ScrollDirection) -> ChunkyScroller {
        let sensitivity = UserPreferences.ScrollMode.ScrollSensitivityProperty.read()
        
        var xAxis = Int32(0)
        var yAxis = Int32(0)
        
        switch direction {
            case .left:
                xAxis = Int32(sensitivity)
            case .right:
                xAxis = Int32(-sensitivity)
            case .down:
                yAxis = Int32(-sensitivity)
            case .up:
                yAxis = Int32(sensitivity)
            default:
                fatalError("half-<direction> scroll directions should not used for smooth scrolling")
        }
        
        let isHorizontalScrollReversed = UserPreferences.ScrollMode.ReverseHorizontalScrollProperty.read()
        let isVerticalScrollReversed = UserPreferences.ScrollMode.ReverseVerticalScrollProperty.read()
        
        if isHorizontalScrollReversed {
            xAxis = -xAxis
        }
        
        if isVerticalScrollReversed {
            yAxis = -yAxis
        }
        
        let frequency = 1.0 / 50.0
        
        return ChunkyScroller(frequency: frequency, xAxis: xAxis, yAxis: yAxis)
    }
    
    private let frequency: TimeInterval
    private let xAxis: Int32
    private let yAxis: Int32
    
    private var timer: Timer?
    
    init(frequency: TimeInterval, xAxis: Int32, yAxis: Int32) {
        self.frequency = frequency
        self.xAxis = xAxis
        self.yAxis = yAxis
    }
    
    @objc func emitScrollEvent() {
        let event = CGEvent.init(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: yAxis, wheel2: xAxis, wheel3: 0)!
        event.post(tap: .cghidEventTap)
    }
    
    func start() {
        if let _ = timer {
            fatalError("Do not call start() more than once.")
        }
        
        emitScrollEvent()
        self.timer = Timer.scheduledTimer(timeInterval: frequency, target: self, selector: #selector(emitScrollEvent), userInfo: nil, repeats: true)
    }
    
    func stop() {
        timer?.invalidate()
        self.timer = nil
    }
}
