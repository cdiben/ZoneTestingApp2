//
//  AppDelegate.swift
//  ZoneTestingApp2
//
//  Created by Christian DiBenedetto on 6/4/25.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Create the window
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.backgroundColor = .systemBackground
        
        // Create the root view controller
        let deviceListVC = DeviceListViewController()
        let navigationController = UINavigationController(rootViewController: deviceListVC)
        
        // Customize navigation bar appearance
        navigationController.navigationBar.prefersLargeTitles = true
        navigationController.navigationBar.tintColor = .systemBlue
        
        // Set the root view controller and make the window visible
        window?.rootViewController = navigationController
        window?.makeKeyAndVisible()
        
        return true
    }



 

}

