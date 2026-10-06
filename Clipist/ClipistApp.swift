import SwiftUI
import AppKit
import Carbon
import UserNotifications
import CoreGraphics // For CGPreflightListenEventAccess

// MARK: - Main App
@main
struct TodoistCaptureApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover = NSPopover()
    var eventMonitor: EventMonitor?
    var hotKeyRef: EventHotKeyRef?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)
        
        // Setup status bar
        setupStatusBar()
        
        // Setup notifications
        setupNotifications()
        
        // Register global hotkey (Cmd+Shift+T)
        registerHotKey()
        
        // Setup popover
        let contentView = ContentView()
        popover.contentSize = NSSize(width: 400, height: 300)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: contentView)
        
        // Monitor clicks outside popover
        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let strongSelf = self, strongSelf.popover.isShown {
                strongSelf.closePopover(sender: nil)
            }
        }
        
        // Add menu items
        setupMenu()
        
        // Check and request permissions on first launch
        checkAndRequestPermissions()
        
        // Show preferences on first run if no API token
        if KeychainHelper.shared.read(forKey: "TodoistAPIToken") == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.showPopover(sender: nil)
            }
        }
    }
    
    // MARK: - Permission Management
    func checkAndRequestPermissions() {
        let hasShownSetup = UserDefaults.standard.bool(forKey: "HasShownInitialSetup")
        if !hasShownSetup {
            UserDefaults.standard.set(true, forKey: "HasShownInitialSetup")
        } else {
            // Always check critical permissions
            if !AXIsProcessTrusted() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.showAccessibilityAlert()
                }
            }
        }
    }
    
    func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Clipist needs accessibility permission to read selected text. Click 'Open Settings' and enable Clipist in the list."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
    
    func setupMenu() {
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "Open Preferences", action: #selector(togglePopover(_:)), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "Todoist Capture")
            button.action = #selector(showMenu)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }
    
    @objc func showMenu() {
        if let menu = statusItem.menu {
            statusItem.popUpMenu(menu)
        }
    }
    
    func setupNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                print("Notification permission granted")
            }
        }
    }
    
    @objc func togglePopover(_ sender: Any?) {
        if popover.isShown {
            closePopover(sender: sender)
        } else {
            showPopover(sender: sender)
        }
    }
    
    func showPopover(sender: Any?) {
        if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
            eventMonitor?.start()
        }
    }
    
    func closePopover(sender: Any?) {
        popover.performClose(sender)
        eventMonitor?.stop()
    }
    
    // MARK: - Hotkey Registration
    func registerHotKey() {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType("TDST".fourCharCodeValue)
        hotKeyID.id = 1
        
        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = OSType(kEventHotKeyPressed)
        
        // Install event handler
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { (_, inEvent, _) -> OSStatus in
            NotificationCenter.default.post(name: .captureHotKeyPressed, object: nil)
            return noErr
        }, 1, &eventType, nil, nil)
        
        if handlerStatus != noErr {
            print("Failed to install event handler. Status: \(handlerStatus)")
            showHotkeyErrorAlert(message: "Failed to install event handler. Status: \(handlerStatus)")
            return
        }

        let modifierFlags: UInt32 = UInt32(cmdKey | shiftKey)
        let keyCode: UInt32 = 0x10

        let hotkeyStatus = RegisterEventHotKey(keyCode, modifierFlags, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        if hotkeyStatus != noErr {
            print("Failed to register hotkey Cmd+Shift+Y. Status: \(hotkeyStatus)")
            let errorMessage = getHotkeyErrorMessage(status: hotkeyStatus)
            showHotkeyErrorAlert(message: errorMessage)
            return
        }

        print("Hotkey Cmd+Shift+Y registered successfully")
        
        // Listen for hotkey notification
        NotificationCenter.default.addObserver(self, selector: #selector(handleHotKey), name: .captureHotKeyPressed, object: nil)
    }
    
    /// Shows an alert to the user when hotkey registration fails
    private func showHotkeyErrorAlert(message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Hotkey Registration Failed"
            alert.informativeText = "\(message)\n\nPlease check if ⌘⇧Y is already in use by another application and try again."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    /// Converts OSStatus error codes to human-readable error messages
    private func getHotkeyErrorMessage(status: OSStatus) -> String {
        switch status {
        case OSStatus(eventHotKeyExistsErr):
            return "The hotkey ⌘⇧Y is already registered by another application"
        case OSStatus(eventHotKeyInvalidErr):
            return "Invalid hotkey combination"
        case OSStatus(eventNotHandledErr):
            return "Event handler not properly installed"
        case OSStatus(memFullErr):
            return "Insufficient memory to register hotkey"
        case OSStatus(paramErr):
            return "Invalid parameters provided to hotkey registration"
        default:
            return "Unknown error occurred while registering hotkey (Status: \(status))"
        }
    }
    
    @objc func handleHotKey() {
        print("Hotkey pressed")

        DispatchQueue.main.async {
            Task {
                do {
                    await self.captureAndSendToTodoist()
                } catch {
                    print("Error in hotkey handler: \(error)")
                }
            }
        }
    }
    
    // MARK: - Text Capture
    /// Waits for the clipboard to change using changeCount, up to a timeout.
    /// Returns the new clipboard string, or nil if timeout is reached.
    /// 
    /// This approach is more reliable than string comparison because:
    /// 1. It uses NSPasteboard.changeCount to detect actual clipboard modifications
    /// 2. It avoids race conditions where the same string might be copied multiple times
    /// 3. It's more efficient than polling string content
    private func waitForClipboardChange(originalChangeCount: Int, timeout: TimeInterval = 2.0) -> String? {
        let pasteboard = NSPasteboard.general
        let start = Date()
        
        while Date().timeIntervalSince(start) < timeout {
            // Check if changeCount has increased (indicating clipboard was modified)
            if pasteboard.changeCount > originalChangeCount {
                // Give a small delay to ensure the content is fully written
                Thread.sleep(forTimeInterval: 0.05)
                
                // Read the new content
                if let newString = pasteboard.string(forType: .string), !newString.isEmpty {
                    return newString
                }
            }
            
            // Sleep for 10ms to avoid busy-waiting
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return nil
    }
    
    func captureSelectedText() -> String? {
        print("Starting text capture")

        let trusted = AXIsProcessTrusted()
        if !trusted {
            print("App doesn't have Accessibility permission")
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options as CFDictionary)
            return nil
        }

        print("Accessibility permission granted")

        guard Thread.isMainThread else {
            print("Clipboard operations must be on main thread")
            return nil
        }

        let pasteboard = NSPasteboard.general
        let initialChangeCount = pasteboard.changeCount
        let oldClipboard = pasteboard.string(forType: .string)

        print("Initial change count: \(initialChangeCount)")

        pasteboard.clearContents()

        if pasteboard.changeCount <= initialChangeCount {
            print("Failed to clear clipboard")
            if let oldContent = oldClipboard {
                pasteboard.clearContents()
                pasteboard.setString(oldContent, forType: .string)
            }
            return nil
        }

        print("Simulating Cmd+C")
        let source = CGEventSource(stateID: .hidSystemState)

        if let cmdCDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true),
           let cmdCUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false) {

            cmdCDown.flags = [.maskCommand]
            cmdCUp.flags = [.maskCommand]

            cmdCDown.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.05)
            cmdCUp.post(tap: .cghidEventTap)

            print("Cmd+C sent")
        } else {
            print("Failed to create key events")
            if let oldContent = oldClipboard {
                pasteboard.clearContents()
                pasteboard.setString(oldContent, forType: .string)
            }
            return nil
        }

        let copiedText = waitForClipboardChange(originalChangeCount: initialChangeCount, timeout: 2.0)
        let postCaptureChangeCount = pasteboard.changeCount

        if let oldContent = oldClipboard {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                let currentChangeCount = pasteboard.changeCount
                let currentContent = pasteboard.string(forType: .string)

                if currentChangeCount <= postCaptureChangeCount {
                    pasteboard.clearContents()
                    pasteboard.setString(oldContent, forType: .string)
                    print("Clipboard restored")
                } else {
                    print("User modified clipboard after capture, not restoring")
                    print("Current content: \(currentContent?.prefix(50) ?? "nil")...")
                }
            }
        }

        if let text = copiedText, !text.isEmpty {
            print("Captured text: \(text.prefix(50))...")
            return text
        }

        print("No text captured from clipboard")
        return nil
    }
    
    // MARK: - Todoist Integration
    func captureAndSendToTodoist() async {
        print("Starting capture and send process")

        let capturedText = await MainActor.run {
            return captureSelectedText()
        }

        guard let text = capturedText else {
            print("No text captured")
            await showNotification(title: "No Text Selected", body: "Please select some text first")
            return
        }

        print("Captured text: \(text.prefix(50))...")

        guard let apiToken = KeychainHelper.shared.read(forKey: "TodoistAPIToken"), !apiToken.isEmpty else {
            print("No API token found")
            await showNotification(title: "API Token Missing", body: "Please set your Todoist API token in settings")
            await MainActor.run {
                showPopover(sender: nil)
            }
            return
        }

        do {
            print("Sending to Todoist")
            try await createTodoistTask(content: text, apiToken: apiToken)
            print("Task created successfully")
            await showNotification(title: "Task Created", body: "Successfully added to Todoist")
        } catch {
            print("Failed to create task: \(error)")
            await showNotification(title: "Error", body: "Failed to create task: \(error.localizedDescription)")
        }
    }
    
    func createTodoistTask(content: String, apiToken: String) async throws {
        // Validate input parameters
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "TodoistAPI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Task content cannot be empty"])
        }
        
        guard !apiToken.isEmpty else {
            throw NSError(domain: "TodoistAPI", code: 2, userInfo: [NSLocalizedDescriptionKey: "API token cannot be empty"])
        }
        
        let url = URL(string: "https://api.todoist.com/rest/v2/tasks")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let task = ["content": content]
        request.httpBody = try JSONEncoder().encode(task)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "TodoistAPI", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to create task"])
        }
    }
    
    func showNotification(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        
        try? await UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Content View
struct ContentView: View {
    @State private var apiToken: String = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingPermissionGuide = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Clipist")
                    .font(.title2)
                    .fontWeight(.bold)
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Settings")
                        .font(.headline)
                    
                    SecureField("Todoist API Token", text: $apiToken)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onChange(of: apiToken) { newValue in
                            KeychainHelper.shared.save(newValue, forKey: "TodoistAPIToken")
                        }
                    
                    Link("Get your API token [settings -> integrations -> developer]", destination: URL(string: "https://todoist.com/app/settings/integrations")!)
                        .font(.caption)
                }
                
                Button("Test Accessibility Permission") {
                    if AXIsProcessTrusted() {
                        alertMessage = "✅ Accessibility permission granted!"
                    } else {
                        alertMessage = "❌ Need Accessibility permission. Opening System Settings..."
                        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                        AXIsProcessTrustedWithOptions(options as CFDictionary)
                    }
                    showingAlert = true
                }
                .buttonStyle(.bordered)
                
                Button("Setup Permissions") {
                    showingPermissionGuide = true
                }
                .buttonStyle(.bordered)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 5) {
                    Text("Usage:")
                        .font(.headline)
                    Text("1. Select any text in any app")
                    Text("2. Press ⌘⇧Y to send to Todoist")
                    Text("3. Check notification for status")
                }
                .font(.caption)
                
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
        }
        .frame(minWidth: 400, minHeight: 500)
        .alert("Result", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            apiToken = KeychainHelper.shared.read(forKey: "TodoistAPIToken") ?? ""
            // Show permission guide on first launch
            let hasShownSetup = UserDefaults.standard.bool(forKey: "HasShownInitialSetup")
            if !hasShownSetup {
                showingPermissionGuide = true
                UserDefaults.standard.set(true, forKey: "HasShownInitialSetup")
            }
        }
        .sheet(isPresented: $showingPermissionGuide) {
            PermissionGuideView()
        }
    }
}

// MARK: - Event Monitor
class EventMonitor {
    private var monitor: Any?
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent?) -> Void
    
    init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent?) -> Void) {
        self.mask = mask
        self.handler = handler
    }
    
    deinit {
        stop()
    }
    
    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
    }
    
    func stop() {
        if monitor != nil {
            NSEvent.removeMonitor(monitor!)
            monitor = nil
        }
    }
}

// MARK: - Permission Guide View
struct PermissionGuideView: View {
    @State private var currentStep = 1
    @State private var accessibilityGranted = false
    @State private var inputMonitoringGranted = false
    @State private var notificationsGranted = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Clipist Setup Guide")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.bottom, 10)
            
            // Step 1: Accessibility
            PermissionStepView(
                step: 1,
                isActive: currentStep == 1,
                icon: "eye.circle.fill",
                title: "Enable Accessibility",
                description: "Allows Clipist to read selected text",
                isGranted: accessibilityGranted
            ) {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                currentStep = 2
            }
            
            // Step 2: Input Monitoring
            PermissionStepView(
                step: 2,
                isActive: currentStep == 2,
                icon: "keyboard.circle.fill",
                title: "Enable Input Monitoring",
                description: "Allows the ⌘⇧Y keyboard shortcut to work",
                isGranted: inputMonitoringGranted
            ) {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
                currentStep = 3
            }
            
            // Step 3: Notifications
            PermissionStepView(
                step: 3,
                isActive: currentStep == 3,
                icon: "bell.circle.fill",
                title: "Enable Notifications",
                description: "Get confirmation when tasks are added",
                isGranted: notificationsGranted
            ) {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    DispatchQueue.main.async {
                        notificationsGranted = granted
                        currentStep = 4
                    }
                }
            }
            
            Spacer()
            
            if currentStep == 4 && accessibilityGranted && inputMonitoringGranted && notificationsGranted {
                VStack(spacing: 15) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.green)
                    
                    Text("Setup Complete!")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("You can now use ⌘⇧Y to send selected text to Todoist")
                        .foregroundColor(.secondary)
                    
                    Button("Close") {
                        if let window = NSApp.keyWindow {
                            window.close()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
            } else if currentStep == 4 {
                Text("Please complete all steps above to finish setup.")
                    .foregroundColor(.red)
                    .padding(.top, 20)
            }
        }
        .padding(30)
        .frame(width: 500, height: 600)
        .onAppear {
            checkPermissions()
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                checkPermissions()
            }
        }
    }
    
    func checkPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
        inputMonitoringGranted = CGPreflightListenEventAccess()
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                notificationsGranted = (settings.authorizationStatus == .authorized)
                print("Accessibility: \(accessibilityGranted), Input Monitoring: \(inputMonitoringGranted), Notifications: \(notificationsGranted)")
            }
        }
    }
}

struct PermissionStepView: View {
    let step: Int
    let isActive: Bool
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let action: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundColor(isActive ? .accentColor : .gray)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Step \(step): \(title)")
                    .font(.headline)
                    .foregroundColor(isActive ? .primary : .secondary)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if isActive {
                    Button("Open Settings") {
                        action()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                if isGranted {
                    Label("Granted", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            
            Spacer()
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isActive ? Color.accentColor.opacity(0.1) : Color.clear)
        )
    }
}

// MARK: - Extensions
extension String {
    var fourCharCodeValue: UInt32 {
        var result: UInt32 = 0
        for char in self.utf8 {
            result = (result << 8) + UInt32(char)
        }
        return result
    }
}

extension Notification.Name {
    static let captureHotKeyPressed = Notification.Name("captureHotKeyPressed")
}
