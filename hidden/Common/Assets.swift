//
//  Assets.swift
//  Hidden Bar
//
//  Created by Peter Luo on 2021/5/28.
//  Copyright © 2021 Dwarves Foundation. All rights reserved.
//

import AppKit

struct Assets {
    // Keep identity stable: reassigning an image can reset status-item length on macOS 27.
    private static let leftChevron = chevron("chevron.left", fallback: "ic_expand")
    private static let rightChevron = chevron("chevron.right", fallback: "ic_collapse")

    static var expandImage: NSImage? {
        Constant.isUsingLTRLanguage ? leftChevron : rightChevron
    }

    static var collapseImage: NSImage? {
        Constant.isUsingLTRLanguage ? rightChevron : leftChevron
    }

    private static func chevron(_ name: String, fallback: String) -> NSImage? {
        if #available(macOS 11.0, *),
           let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
            let image = symbol.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)) ?? symbol
            image.isTemplate = true
            return image
        }
        return NSImage(named: NSImage.Name(fallback))
    }
}
