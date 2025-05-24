//
// Trio
// BaseIntentsRequest.swift
// Created by Deniz Cengiz on 2025-01-01.
// Last edited by Deniz Cengiz on 2025-03-01.
// Most contributions by Pierre L and Deniz Cengiz.
//
// Documentation available under: https://triodocs.org/

import Foundation
import Swinject

@available(iOS 16.0, *) protocol IntentsRequestType {
    var intentRequest: BaseIntentsRequest { get set }
}

@available(iOS 16.0, *) class BaseIntentsRequest: NSObject, Injectable {
    @Injected() var tempTargetsStorage: TempTargetsStorage!
    @Injected() var settingsManager: SettingsManager!
    @Injected() var storage: TempTargetsStorage!
    @Injected() var fileStorage: FileStorage!
    @Injected() var carbsStorage: CarbsStorage!
    @Injected() var glucoseStorage: GlucoseStorage!
    @Injected() var apsManager: APSManager!
    @Injected() var overrideStorage: OverrideStorage!
    @Injected() var liveActivityManager: LiveActivityManager!

    let resolver: Resolver

    let coredataContext = CoreDataStack.shared.newTaskContext()
    let viewContext = CoreDataStack.shared.persistentContainer.viewContext

    override init() {
        resolver = TrioApp.resolver
        super.init()
        injectServices(resolver)
    }
}
