//
//  Element.swift
//  Vimac
//
//  Created by Dexter Leng on 5/9/20.
//  Copyright © 2020 Dexter Leng. All rights reserved.
//

import Cocoa
import AXSwift

class Element {
    let rawElement: AXUIElement
    let frame: NSRect
    let actions: [String]
    let role: String
    
    var clippedFrame: NSRect?
    
    static func initialize(rawElement: AXUIElement) -> Element? {
        let uiElement = UIElement.init(rawElement)
        let valuesOptional = try? uiElement.getMultipleAttributes([.size, .position, .role])
        
        guard let values = valuesOptional else {
            return nil
        }

        guard let size: NSSize = values[Attribute.size] as! NSSize? else { return nil }
        guard let position: NSPoint = values[Attribute.position] as! NSPoint? else { return nil }
        guard let role: String = values[Attribute.role] as! String? else { return nil }
        let frame = NSRect(origin: position, size: size)

        guard let actions = try? uiElement.actionsAsStrings() else { return nil }
        
        return Element.init(rawElement: rawElement, frame: frame, actions: actions, role: role)
    }
    
    init(rawElement: AXUIElement, frame: NSRect, actions: [String], role: String) {
        self.rawElement = rawElement
        self.frame = frame
        self.actions = actions
        self.role = role
    }
    
    func setClippedFrame(_ clippedFrame: NSRect) {
        self.clippedFrame = clippedFrame
    }
}
