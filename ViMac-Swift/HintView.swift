//
//  HintView.swift
//  ViMac-Swift
//
//  Created by Dexter Leng on 15/9/19.
//  Copyright © 2019 Dexter Leng. All rights reserved.
//

import Cocoa
import AXSwift

class HintView: NSTextField {
    static let borderColor = NSColor(red: 212 / 255, green: 172 / 255, blue: 58 / 255, alpha: 1)
    static let backgroundColor = NSColor(red: 255 / 255, green: 224 / 255, blue: 112 / 255, alpha: 1)
    static let untypedHintColor = NSColor.black
    static let typedHintColor = NSColor(red: 212 / 255, green: 172 / 255, blue: 58 / 255, alpha: 1)
    
    var associatedElement: UIElement?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    func initializeHint(hintText: String, typed: String) {
        let attr = NSMutableAttributedString(string: hintText)
        let range = NSMakeRange(0, hintText.count)
        attr.addAttributes([NSAttributedString.Key.foregroundColor : HintView.untypedHintColor], range: range)
        if hintText.starts(with: typed) {
            let typedRange = NSMakeRange(0, typed.count)
            attr.addAttributes([NSAttributedString.Key.foregroundColor : HintView.typedHintColor], range: typedRange)
        }
        self.stringValue = hintText
        self.attributedStringValue = attr
        
        self.wantsLayer = true
        self.isBordered = true
        self.drawsBackground = true
        
        self.backgroundColor = HintView.backgroundColor
        
        self.layer?.backgroundColor = HintView.backgroundColor.cgColor
        self.layer?.borderColor = HintView.borderColor.cgColor
        self.layer?.borderWidth = 1
        self.layer?.cornerRadius = 5
        self.font = NSFont.boldSystemFont(ofSize: 10)
        
        self.sizeToFit()
    }
    
    func updateTypedText(typed: String) {
        let hintText = self.attributedStringValue.string
        let attr = NSMutableAttributedString(string: hintText)
        let range = NSMakeRange(0, hintText.count)
        attr.addAttributes([NSAttributedString.Key.foregroundColor : HintView.untypedHintColor], range: range)
        if hintText.lowercased().starts(with: typed.lowercased()) {
            let typedRange = NSMakeRange(0, typed.count)
            attr.addAttributes([NSAttributedString.Key.foregroundColor : HintView.typedHintColor], range: typedRange)
        }
        self.attributedStringValue = attr
    }
    
    // the first NSTextField that get's drawn to screen is made active, which changes the
    // first hint's text color to white. This prevents the hints from being made active.
    override func becomeFirstResponder() -> Bool {
        return false
    }
}
