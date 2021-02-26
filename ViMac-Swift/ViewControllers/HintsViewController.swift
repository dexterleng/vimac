//
//  HintsViewController.swift
//  Vimac
//
//  Created by Dexter Leng on 24/2/21.
//  Copyright © 2021 Dexter Leng. All rights reserved.
//

import Cocoa

class HintsViewController: NSViewController {
    let hints: [Hint]
    let textSize: CGFloat
    var typed: String

    var hintViews: [HintView]!
    
    init(hints: [Hint], textSize: CGFloat, hintCharacters: String, typed: String = "") {
        self.hints = hints
        self.textSize = textSize
        self.typed = typed
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    override func loadView() {
        self.view = NSView()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        
        self.hintViews = hints
            .map { renderHint($0) }
            .compactMap({ $0 })

        for hintView in self.hintViews {
            self.view.addSubview(hintView)
        }
    }
    
    func updateTyped(typed: String) {
        guard let hintViews = self.hintViews else { return }
        
        self.typed = typed
        hintViews.forEach { hintView in
            hintView.isHidden = true
            if hintView.hintTextView!.stringValue.starts(with: typed.uppercased()) {
                hintView.updateTypedText(typed: typed)
                hintView.isHidden = false
            }
        }
    }
    
    func rotateHints() {
        for hintView in hintViews {
            hintView.removeFromSuperview()
        }
        
        let shuffledHintViews = hintViews.shuffled()
        for hintView in shuffledHintViews {
            self.view.addSubview(hintView)
        }
        self.hintViews = shuffledHintViews
    }
    
    func renderHint(_ hint: Hint) -> HintView? {
        let view = HintView(associatedElement: hint.element, hintTextSize: CGFloat(textSize), hintText: hint.text, typedHintText: "")
        guard let elementFrame = self.elementFrame(hint.element) else { return nil }
        let elementCenter: NSPoint = GeometryUtils.center(elementFrame)

        let hintOrigin = NSPoint(
            x: elementCenter.x - (view.intrinsicContentSize.width / 2),
            y: elementCenter.y - (view.intrinsicContentSize.height / 2)
        )

        if hintOrigin.x.isNaN || hintOrigin.y.isNaN {
            return nil
        }

        view.frame.origin = hintOrigin
        return view
    }
    
    func elementFrame(_ element: Element) -> NSRect? {
        guard let window = self.view.window else { return nil }

        let globalFrame = GeometryUtils.convertAXFrameToGlobal(
            element.frame)
        let windowFrame = window.convertFromScreen(globalFrame)
        return window.contentView?.convert(windowFrame, to: self.view)
    }
}
