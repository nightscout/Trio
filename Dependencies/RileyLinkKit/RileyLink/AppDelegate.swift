//
//  AppDelegate.swift
//  RileyLink
//
//  Created by Nathan Racklyeft on 4/22/16.
//  Copyright © 2016 Pete Schwamb. All rights reserved.
//

import UIKit
import SwiftUI
import CoreData
import LoopKitUI
import RileyLinkKit


@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    private(set) lazy var deviceDataManager = DeviceDataManager()
    
    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        if let navController = self.window?.rootViewController as? UINavigationController {
            let mainViewController = MainViewController(deviceDataManager: deviceDataManager, insulinTintColor: .orange, guidanceColors: GuidanceColors(acceptable: .primary, warning: .yellow, critical: .red))
            navController.pushViewController(mainViewController, animated: false)
        }
        
        return true
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
        NSLog(#function)
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
        NSLog(#function)
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
        NSLog(#function)
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
        NSLog(#function)
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        NSLog(#function)
    }
    
    // MARK: - 3D Touch
    
    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(false)
    }    
}


private func applicationDocumentsDirectory() -> URL {
    return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last!
}

