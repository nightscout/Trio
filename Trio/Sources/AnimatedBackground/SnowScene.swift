//
// Trio
// SnowScene.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-01-01.
// Most contributions by Ivan Valkou.
//
// Documentation available under: https://triodocs.org/

import Foundation
import SpriteKit

class SnowScene: SKScene {
    let snowEmitterNode = SKEmitterNode(fileNamed: "snow.sks")

    override func didMove(to _: SKView) {
        guard let snowEmitterNode = snowEmitterNode else { return }
        snowEmitterNode.particleSize = CGSize(width: 50, height: 50)
        snowEmitterNode.particleLifetime = 2
        snowEmitterNode.particleLifetimeRange = 6
        addChild(snowEmitterNode)
        subscribe()
    }

    private func subscribe() {
        Foundation.NotificationCenter.default.addObserver(
            self,
            selector: #selector(didEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        Foundation.NotificationCenter.default.addObserver(
            self,
            selector: #selector(willEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    override func didChangeSize(_: CGSize) {
        guard let snowEmitterNode = snowEmitterNode else { return }
        snowEmitterNode.particlePosition = CGPoint(x: size.width / 2, y: size.height)
        snowEmitterNode.particlePositionRange = CGVector(dx: size.width, dy: size.height)
    }

    @objc private func didEnterBackground() {
        isPaused = true
    }

    @objc private func willEnterForeground() {
        isPaused = false
    }
}
