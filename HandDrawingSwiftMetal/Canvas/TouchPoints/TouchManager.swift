//
//  TouchManager.swift
//  HandDrawingSwiftMetal
//
//  Created by Eisuke Kusachi on 2024/04/01.
//

import UIKit

typealias TouchHashValue = Int

final class TouchManager {

    // When a gesture is recognized as 'drawing' during finger input, the touchManager manages only one finger.
    // So we use the first value in the array.
    var hashValueForFingerDrawing: TouchHashValue? {
        touchPointsDictionary.keys.first
    }

    // During pencil input, the beginning of the array may fail
    // due to occasional palm contact with the screen.
    var hashValueForPencilDrawing: TouchHashValue? {
        for key in touchPointsDictionary.keys {
            if touchPointsDictionary[key]?.map({
                $0.type
            }).contains(.pencil) == true {
                return key
            }
        }
        return nil
    }

    private (set) var touchPointsDictionary: [TouchHashValue: [TouchPoint]] = [:]

    func appendFingerTouchesToTouchPointsDictionary(_ event: UIEvent?, in view: UIView) {
        event?.allTouches?.forEach { touch in
            guard touch.type != .pencil else { return }

            let hashValue: TouchHashValue = touch.hashValue

            if touch.phase == .began && touchPointsDictionary[hashValue] == nil {
                touchPointsDictionary[hashValue] = []
            }

            if touchPointsDictionary.keys.contains(hashValue) {
                let touchPoint = TouchPoint(touch: touch, view: view)
                touchPointsDictionary[hashValue]?.append(touchPoint)
            }
        }
    }

    func appendPencilTouchesToTouchPointsDictionary(_ event: UIEvent?, in view: UIView) {
        event?.allTouches?.forEach { touch in
            guard touch.type == .pencil else { return }

            let hashValue: TouchHashValue = touch.hashValue

            if touch.phase == .began && touchPointsDictionary[hashValue] == nil {
                touchPointsDictionary[hashValue] = []
            }

            if touchPointsDictionary.keys.contains(hashValue),
               let coalescedTouches = event?.coalescedTouches(for: touch) {

                for index in 0 ..< coalescedTouches.count {
                    let touchPoint = TouchPoint(touch: coalescedTouches[index], view: view)
                    touchPointsDictionary[hashValue]?.append(touchPoint)
                }
            }
        }
    }

    func removeValuesOnTouchesEnded(touches: Set<UITouch>) {
        for touch in touches where touch.phase == .ended || touch.phase == .cancelled {
            touchPointsDictionary.removeValue(forKey: touch.hashValue)
        }
    }

    func clearTouchPointsDictionary() {
        touchPointsDictionary.removeAll()
    }

}

extension TouchManager {

    func getTouchPoints(with hashValue: TouchHashValue) -> [TouchPoint]? {
        touchPointsDictionary[hashValue]
    }
    func getLatestTouchPhase(with hashValue: TouchHashValue) -> UITouch.Phase? {
        touchPointsDictionary[hashValue]?.last?.phase
    }

}
