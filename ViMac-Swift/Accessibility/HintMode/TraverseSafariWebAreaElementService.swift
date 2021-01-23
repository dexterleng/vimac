//
//  TraverseSafariWebAreaElementService.swift
//  Vimac
//
//  Created by Dexter Leng on 19/12/20.
//  Copyright © 2020 Dexter Leng. All rights reserved.
//

import Cocoa
import AXSwift

class TraverseSafariWebAreaElementService : TraverseElementService {
    let element: Element
    let app: NSRunningApplication
    let windowElement: Element
    let containerElement: Element?
    
    required init(element: Element, app: NSRunningApplication, windowElement: Element, containerElement: Element?) {
        self.element = element
        self.app = app
        self.windowElement = windowElement
        self.containerElement = containerElement
    }
    
    func perform() -> ElementTreeNode? {
        if !isElementVisible() {
            return nil
        }
        
        let recursiveChildren = try? getRecursiveChildrenThroughSearchPredicate()
        let recursiveChildrenNodes = recursiveChildren?
            .map { SafariWebAreaElementTreeNode(root: $0, children: nil) }
        return SafariWebAreaElementTreeNode(root: element, children: recursiveChildrenNodes)
    }
    
    private func isElementVisible() -> Bool {
        containerElement?.frame.intersects(element.frame) ?? true
    }
    
    private func getRecursiveChildrenThroughSearchPredicate() throws -> [Element]? {
        let query: [String: Any] = [
            "AXDirection": "AXDirectionNext",
            "AXImmediateDescendantsOnly": false,
            "AXResultsLimit": -1,
            "AXVisibleOnly": true,
            "AXSearchKey": [
                "AXButtonSearchKey",
                "AXCheckBoxSearchKey",
                "AXControlSearchKey",
                "AXGraphicSearchKey",
                "AXLinkSearchKey",
                "AXRadioGroupSearchKey",
                "AXTextFieldSearchKey"
            ]
        ]
        let rawElements: [AXUIElement]? = try UIElement(element.rawElement).parameterizedAttribute("AXUIElementsForSearchPredicate", param: query)
        let elements = rawElements?
            .map({ Element.initialize(rawElement: $0) })
            .compactMap({ $0 })
        return elements
    }
}

