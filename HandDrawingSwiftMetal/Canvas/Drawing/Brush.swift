//
//  Brush.swift
//  HandDrawingSwiftMetal
//
//  Created by Eisuke Kusachi on 2023/03/28.
//

import Foundation

struct Brush {
    
    static let minDiameter: Int = 1
    static let maxDiameter: Int = 64
    
    var rgb: (Int, Int, Int) = (0, 0, 0)
    var alpha: Int = 200
    var diameter: Int = 8
    var blurSize: Float = initBlurSize
    
    init(rgb: (Int, Int, Int)? = nil, alpha: Int? = nil, diameter: Int? = nil) {
        if let rgb = rgb {
            self.rgb = rgb
        }
        if let alpha = alpha {
            self.alpha = alpha
        }
        if let diameter = diameter {
            self.diameter = diameter
        }
    }
    
    var blurredSize: BlurredSize {
        return BlurredSize(diameter: diameter, blurSize: blurSize)
    }
    
    mutating func setR(_ value: Int) {
        rgb = (value, rgb.1, rgb.2)
    }
    mutating func setG(_ value: Int) {
        rgb = (rgb.0, value, rgb.2)
    }
    mutating func setB(_ value: Int) {
        rgb = (rgb.0, rgb.1, value)
    }
    
    mutating func setValue(rgba: (Int, Int, Int, Int)? = nil, diameter: Int? = nil) {
        if let rgba = rgba {
            self.rgb = (rgba.0, rgba.1, rgba.2)
            self.alpha = rgba.3
        }
        if let diameter = diameter {
            self.diameter = diameter
        }
    }
    mutating func setValue(rgb: (Int, Int, Int)? = nil, alpha: Int? = nil, diameter: Int? = nil) {
        if let rgb = rgb {
            self.rgb = rgb
        }
        if let alpha = alpha {
            self.alpha = alpha
        }
        if let diameter = diameter {
            self.diameter = diameter
        }
    }
}
