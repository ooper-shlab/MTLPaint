//
//  AAPLMathUtilities.swift
//  MTLPaint
//
//  Translated by OOPer in cooperation with shlab.jp, on 2019/4/26.
//
/*
 The functions below are taken from AAPLMathUtilities.h, AAPLMathUtilities.m
 of Apple's sample code Deferred Lighting, and translated into Swift.
 https://developer.apple.com/documentation/metal/deferred_lighting?language=objc
 See: https://forums.developer.apple.com/thread/89682
 */
/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Header for vector, matrix, and quaternion math utility functions useful for 3D graphics
 rendering with Metal
*/
/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of vector, matrix, and quaternion math utility functions useful for 3D graphics
 rendering with Metal
*/

import Foundation
import simd

extension float4x4 {
    static func orthoRightHand(_ left: Float, _ right: Float, _ bottom: Float, _ top: Float, _ nearZ: Float, _ farZ: Float) -> float4x4 {
        return float4x4([2 / (right - left), 0, 0, 0],
                        [0, 2 / (top - bottom), 0, 0],
                        [0, 0, -1 / (farZ - nearZ), 0],
                        [(left + right) / (left - right), (top + bottom) / (bottom - top), nearZ / (nearZ - farZ), 1])
    }
    
    static func orthoLeftHand(_ left: Float, _ right: Float, _ bottom: Float, _ top: Float, _ nearZ: Float, _ farZ: Float) -> float4x4 {
        return float4x4([2 / (right - left), 0, 0, 0],
                        [0, 2 / (top - bottom), 0, 0],
                        [0, 0, 1 / (farZ - nearZ), 0],
                        [(left + right) / (left - right), (top + bottom) / (bottom - top), nearZ / (nearZ - farZ), 1])
    }

}

/*
 Some other additions...
 */
extension float4x4 {
    static let identity = float4x4(1)
}
