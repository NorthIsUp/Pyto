//
//  SceneDelagate.swift
//  Pyto
//
//  Created by Adrian Labbé on 08-06-19.
//  Copyright © 2019 Adrian Labbé. All rights reserved.
//

import UIKit
import StoreKit
import SwiftUI

/// The scene delegate.
@objc class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    
    /// The document browser associated with this scene.
    var documentBrowserViewController: DocumentBrowserViewController? {
        return window?.rootViewController as? DocumentBrowserViewController
    }
    
    /// Shows onboarding if needed.
    func showOnboarding() {
        checkIfUnlocked(on: window)
    }
    
    /// The scene state.
    var sceneStateStore = SceneStateStore()
    
    /// Opens a document after the scene is shown.
    ///
    /// - Parameters:
    ///     - url: The URL to open.
    ///     - run: A boolean indicating whether the script should be executed.
    ///     - isShortcut: A boolean indicating whether the script is executed from Shortcuts.
    func openDocument(at url: URL, run: Bool, isShortcut: Bool) {
        _ = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true, block: { (timer) in
            if let doc = self.documentBrowserViewController {
                doc.revealDocument(at: url, importIfNeeded: false) { (url_, _) in
                    doc.openDocument(url_ ?? url, run: run, isShortcut: isShortcut)
                }
                timer.invalidate()
            }
        })
    }
    
    // MARK: - Scene delegate
    
    var window: UIWindow?
    
    @available(iOS 13.0, *)
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        
        #if VPP
        changingUserDefaultsInAppPurchasesValues = true
        isPurchased.boolValue = true
        changingUserDefaultsInAppPurchasesValues = true
        isLiteVersion.boolValue = false
        isUnlocked = true
        isReceiptChecked = true
        #else
        verifyReceipt()
        #endif
        
        if let vc = SceneDelegate.viewControllerToShow {
            SceneDelegate.viewControllerToShow = nil
            
            let blankVC = ViewController()
            blankVC.sceneSession = session
            blankVC.viewControllerToPresent = vc
            blankVC.completion = SceneDelegate.viewControllerDidShow
            window?.rootViewController = blankVC
            
            return
        }
        
        window?.tintColor = ConsoleViewController.choosenTheme.tintColor
        window?.overrideUserInterfaceStyle = ConsoleViewController.choosenTheme.userInterfaceStyle
        if let window = self.window {
            SceneDelegate.windows.append(window)
        }
        
        if connectionOptions.urlContexts.count > 0 {
            self.scene(scene, openURLContexts: connectionOptions.urlContexts)
            return
        }
        
        if connectionOptions.userActivities.count > 0 {
            self.scene(scene, continue: connectionOptions.userActivities.first!)
            return
        }
        
        if let item = connectionOptions.shortcutItem, let windowScene = scene as? UIWindowScene {
            self.windowScene(windowScene, performActionFor: item, completionHandler: { _ in })
            return
        }
        
        if let restorationActivity = session.stateRestorationActivity, #available(iOS 14.0, *) {
            restoreActivity(restorationActivity, session: session)
        }
    }
    
    @available(iOS 13.0, *)
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        
        func open() {
            if shortcutItem.type == "PyPi" {
                let vc = UIStoryboard(name: "Main", bundle: Bundle.main).instantiateViewController(withIdentifier: "pypi")
                let navVC = UINavigationController(rootViewController: vc)
                navVC.modalPresentationStyle = .formSheet
                windowScene.windows.first?.topViewController?.present(navVC, animated: true, completion: nil)
                completionHandler(true)
            } else if shortcutItem.type == "REPL" {
                windowScene.windows.first?.topViewController?.present(UIStoryboard(name: "Main", bundle: Bundle.main).instantiateViewController(withIdentifier: "repl"), animated: true, completion: nil)
                completionHandler(true)
            } else {
                completionHandler(false)
            }
        }
        
        _ = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true, block: { (timer) in
            
            var otherCondition = true
            if shortcutItem.type == "REPL" {
                otherCondition = Python.shared.isSetup
            }
            
            if self.documentBrowserViewController != nil && otherCondition {
                
                open()
                
                timer.invalidate()
            }
        })
    }
    
    @available(iOS 13.0, *)
    func sceneWillResignActive(_ scene: UIScene) {
        #if MAIN
        (UIApplication.shared.delegate as? AppDelegate)?.copyModules()
        ((window?.rootViewController?.presentedViewController as? UINavigationController)?.viewControllers.first as? EditorSplitViewController)?.editor?.save()
        #endif
    }
    
    @available(iOS 13.0, *)
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        continueActivity(userActivity)
    }
    
    @available(iOS 13.0, *)
    func sceneDidDisconnect(_ scene: UIScene) {
        ((window?.rootViewController?.presentedViewController as? UINavigationController)?.viewControllers.first as? EditorSplitViewController)?.editor?.save()
    }
    
    @available(iOS 13.0, *)
    func sceneDidEnterBackground(_ scene: UIScene) {
        ((window?.rootViewController?.presentedViewController as? UINavigationController)?.viewControllers.first as? EditorSplitViewController)?.editor?.save()
    }
    
    @available(iOS 13.0, *)
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        
        guard let inputURL = URLContexts.first?.url else {
            return
        }
        
        if inputURL.scheme == "pyto" {
            if inputURL.host == "upgrade" { // Upgrade
                if isLiteVersion.boolValue, isPurchased.boolValue {
                    purchase(id: .upgrade, window: window)
                }
            } else if inputURL.host == "inspector" { // The inspector
                guard let query = inputURL.query?.removingPercentEncoding, let data = query.data(using: .utf8) else {
                    return
                }
                                
                do {
                    let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                    
                    let vc = (scene as? UIWindowScene)?.windows.first?.topViewController
                    let controller = UIHostingController(rootView: JSONBrowserNavigationView(items: dict ?? [:], dismiss: {
                        vc?.dismiss(animated: true, completion: nil)
                    }))
                    vc?.present(controller, animated: true, completion: nil)
                } catch {
                    NSLog("%@", error.localizedDescription)
                }
            } else if inputURL.host == "callback" { // I don't remember what that does hahhahah
                PyCallbackHelper.url = inputURL.absoluteString
            } else if inputURL.host == "x-callback" { // x-callback
                PyCallbackHelper.cancelURL = inputURL.queryParameters?["x-cancel"]
                PyCallbackHelper.errorURL = inputURL.queryParameters?["x-error"]
                PyCallbackHelper.successURL = inputURL.queryParameters?["x-success"]
            
                
                guard let documentBrowserViewController = documentBrowserViewController else {
                    window?.rootViewController?.dismiss(animated: true, completion: {
                        self.scene(scene, openURLContexts: URLContexts)
                    })
                    return
                }
                
                if let code = inputURL.queryParameters?["code"] {
                    PyCallbackHelper.code = code
                    documentBrowserViewController.run(code: code)
                }
            } else if inputURL.pathComponents.first == "widget" { // Open script from widget
                let bookmarkString = inputURL.lastPathComponent
                if let bookmarkData = Data(base64Encoded: bookmarkString) {
                    do {
                        var isStale = false
                        let url = try URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &isStale)
                        _ = url.startAccessingSecurityScopedResource()
                        openDocument(at: url, run: true, isShortcut: false)
                    } catch {
                        print(error.localizedDescription)
                    }
                }
            }
            
            return
        }
        
        // Open script
        
        guard let documentBrowserViewController = documentBrowserViewController else {
            window?.rootViewController?.dismiss(animated: true, completion: {
                self.scene(scene, openURLContexts: URLContexts)
            })
            return
        }
        
        // Ensure the URL is a file URL
        guard inputURL.isFileURL else {
            
            guard let query = inputURL.query?.removingPercentEncoding else {
                return
            }
            
            // Run code passed to the URL
            documentBrowserViewController.run(code: query)
            
            return
        }
        
        _ = inputURL.startAccessingSecurityScopedResource()
        
        // Reveal / import the document at the URL
        
        documentBrowserViewController.revealDocument(at: inputURL, importIfNeeded: true, completion: { (url, _) in
            
            documentBrowserViewController.openDocument(url ?? inputURL, run: false)
        })
    }
}
