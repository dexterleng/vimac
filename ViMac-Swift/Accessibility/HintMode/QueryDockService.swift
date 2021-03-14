//
//  QueryDockService.swift
//  Vimac
//
//  Created by Dexter Leng on 14/3/21.
//  Copyright © 2021 Dexter Leng. All rights reserved.
//

import Cocoa
import AXSwift

class QueryDockService {
    func perform() -> [Element]? {
        guard let dock = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.dock" }) else {
            return nil
        }
        
        guard let dockAX = Application(dock) else {
            return nil
        }
        
        guard let dockAXChildren: [AXUIElement] = try? dockAX.attribute(.children) else {
            return nil
        }
        
        guard let listAX = dockAXChildren.first.map({ UIElement($0) }) else {
            return nil
        }
        
        guard let dockItems: [AXUIElement] = try? listAX.attribute(.children) else {
            return nil
        }
        
        return dockItems
            .map({ Element.initialize(rawElement: $0) })
            .compactMap({ $0 })
    }
}
