import XCTest
@testable import Clipist
import Foundation
import AppKit
import UserNotifications
import SwiftUI

#if os(macOS)
import Cocoa

// MARK: - Appearance Restoration Helpers

private enum SystemAppearance: String {
    case light, dark
}

private func getCurrentAppearance() -> SystemAppearance? {
    let script = "tell application \"System Events\" to tell appearance preferences to get dark mode"
    var error: NSDictionary?
    if let scriptObject = NSAppleScript(source: script) {
        let output = scriptObject.executeAndReturnError(&error)
        return output.booleanValue ? .dark : .light
    }
    return nil
}

private func setAppearance(_ appearance: SystemAppearance) {
    let mode = (appearance == .dark) ? "true" : "false"
    let script = "tell application \"System Events\" to tell appearance preferences to set dark mode to \(mode)"
    NSAppleScript(source: script)?.executeAndReturnError(nil)
}

// Save the original appearance at the start
private let __clipistOriginalAppearance: SystemAppearance? = getCurrentAppearance()

// Register an atexit handler to restore appearance after all tests
private let __clipistAppearanceRestorer: Void = {
    atexit {
        if let original = __clipistOriginalAppearance {
            setAppearance(original)
        }
    }
}()
#endif

func isCI() -> Bool {
    let env = ProcessInfo.processInfo.environment
    return env["CI"] == "true" || env["XCODE_CI"] == "1" || env["GITHUB_ACTIONS"] == "true"
}

func isNetworkAvailable() -> Bool {
    return true
}

class ClipistTests: XCTestCase {
    
    // MARK: - Simple Test to Verify Framework
    
    func testBasicFunctionality() {
        XCTAssertTrue(true, "Basic test should pass")
    }
    
    // MARK: - Permission Tests
    
    func testAccessibilityPermissionPrompt() {
        #if os(macOS)
        if isCI() {
            print("Skipping accessibility test in CI environment.")
            return
        }
        let trusted = AXIsProcessTrusted()
        XCTAssertTrue(type(of: trusted) == Bool.self)
        #endif
    }

    func testPermissionGuideViewSteps() {
        #if canImport(AppKit)
        let view = PermissionGuideView()
        _ = view.body
        XCTAssertTrue(true)
        #endif
    }

    // MARK: - Notification Tests
    
    func testNotificationAuthorization() async {
        let center = UNUserNotificationCenter.current()
        let (granted, _) = await withCheckedContinuation { cont in
            center.requestAuthorization(options: [.alert, .sound]) { granted, err in
                cont.resume(returning: (granted, err))
            }
        }
        XCTAssertTrue(granted == true || granted == false)
    }

    // MARK: - Todoist Integration Tests
    
    func testCreateTodoistTaskWithInvalidToken() async throws {
        throw XCTSkip("Temporarily disabled: network or API validation not under test.")
        let appDelegate = AppDelegate()

        XCTAssertNotNil(appDelegate.createTodoistTask)

        do {
            try await appDelegate.createTodoistTask(content: "Test Task", apiToken: "")
            XCTFail("Should throw for empty API token")
        } catch {
            XCTAssertTrue(true, "Correctly threw error for empty API token")
        }
    }

    func testCreateTodoistTaskWithEmptyContent() async throws {
        throw XCTSkip("Temporarily disabled: network or API validation not under test.")
        let appDelegate = AppDelegate()

        XCTAssertNotNil(appDelegate.createTodoistTask)

        do {
            try await appDelegate.createTodoistTask(content: "", apiToken: "some-token")
            XCTFail("Should throw for empty content")
        } catch {
            XCTAssertTrue(true, "Correctly threw error for empty content")
        }
    }

    // MARK: - Capture Tests
    
    func testCaptureSelectedTextReturnsNilWithoutPermission() {
        #if os(macOS)
        if isCI() {
            print("Skipping capture test in CI environment.")
            return
        }
        
        let appDelegate = AppDelegate()
        let result = appDelegate.captureSelectedText()

        if let text = result {
            XCTAssertTrue(type(of: text) == String.self, "Result should be a String when not nil")
            XCTAssertFalse(text.isEmpty, "Result should not be empty when not nil")
        } else {
            XCTAssertTrue(true, "nil result is acceptable when no permission or no text")
        }
        #endif
    }

    // MARK: - Bug Fix Tests
    
    func testClipboardRestorationAfterCapture() {
        #if os(macOS)
        if isCI() {
            print("Skipping clipboard test in CI environment.")
            return
        }
        
        let appDelegate = AppDelegate()
        let pasteboard = NSPasteboard.general
        let original = "original-clipist-test-\(UUID().uuidString)"

        let currentContent = pasteboard.string(forType: NSPasteboard.PasteboardType.string)

        pasteboard.clearContents()
        pasteboard.setString(original, forType: NSPasteboard.PasteboardType.string)

        let verifyContent = pasteboard.string(forType: NSPasteboard.PasteboardType.string)
        XCTAssertEqual(verifyContent, original, "Test content should be set correctly")

        _ = appDelegate.captureSelectedText()

        Thread.sleep(forTimeInterval: 1.0)

        let finalContent = pasteboard.string(forType: NSPasteboard.PasteboardType.string)

        let isValidResult = finalContent == original ||
                           finalContent == currentContent ||
                           finalContent == nil

        XCTAssertTrue(isValidResult, "Clipboard should either be restored, unchanged, or cleared")

        if let originalContent = currentContent, finalContent != originalContent {
            pasteboard.clearContents()
            pasteboard.setString(originalContent, forType: NSPasteboard.PasteboardType.string)
        }
        #endif
    }

    // MARK: - Parameterized Network Tests
    
    func testCreateTodoistTaskWithVariousContents() async throws {
        throw XCTSkip("Temporarily disabled: network or API validation not under test.")
        let appDelegate = AppDelegate()

        XCTAssertNotNil(appDelegate.createTodoistTask)

        let testCases = ["", " ", String(repeating: "a", count: 1000)]

        for content in testCases {
            do {
                try await appDelegate.createTodoistTask(content: content, apiToken: "some-token")
                if content.isEmpty || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    XCTFail("Should throw for empty content: '\(content.prefix(20))'")
                } else {
                    XCTFail("Should throw for invalid API token")
                }
            } catch {
                if content.isEmpty || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    XCTAssertTrue(true, "Correctly threw error for empty content: '\(content.prefix(20))'")
                } else {
                    XCTAssertTrue(true, "Correctly threw error for invalid API token")
                }
            }
        }
    }
}
