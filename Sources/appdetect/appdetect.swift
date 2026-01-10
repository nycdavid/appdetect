// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import AppKit


struct AXWindowInfo {
    let title: String?
    let document: String?
}

@main
struct appdetect {
    static func main() {
        // 1. listen on a socket
        // 2. request handling
        //  - request comes in -> focused app is queried
        //  - app information + metadata (as JSON) is returned via socket
        //

        // Create UNIX socket
        print("exe:", CommandLine.arguments[0])
        print("trusted:", AXIsProcessTrusted())
        let serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            perror("socket")
            exit(1)
        }
        defer { close(serverFD) }
        
        // Set up socket for listening
        setupSocket(serverFD: serverFD)

        var currentAppName = "unknown"
        var axwi: AXWindowInfo?

        let _ = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let appPID = app?.processIdentifier

            if let pid = appPID {
                let appAX = AXUIElementCreateApplication(pid)

                var focusedWindowValue: CFTypeRef?
                let err = AXUIElementCopyAttributeValue(appAX,
                                                       kAXFocusedWindowAttribute as CFString,
                                                       &focusedWindowValue)

                guard err == .success,
                      let win = focusedWindowValue,
                      CFGetTypeID(win) == AXUIElementGetTypeID()
                else {
                    print(err.rawValue)
                    return
                }

                let winAX = win as! AXUIElement
                func copyString(_ attr: CFString) -> String? {
                    var value: CFTypeRef?
                    let e = AXUIElementCopyAttributeValue(winAX, attr, &value)
                    guard e == .success,
                          let v = value,
                          CFGetTypeID(v) == CFStringGetTypeID()
                    else { return nil }
                    return v as? String
                }


                // Many apps put the “file/document” portion here.
                let title = copyString(kAXTitleAttribute as CFString)
                let document = copyString(kAXDocumentAttribute as CFString)

                axwi = AXWindowInfo(title: title, document: document)
            }

            currentAppName = app?.localizedName ?? "unknown"
            currentAppName = currentAppName
        }

        DispatchQueue.global().async {
            // Accept loop
            while true {
                let clientFD = accept(serverFD, nil, nil)
                if clientFD < 0 {
                    perror("accept")
                    continue
                }

                var fullInfo = ""
                if let ft = axwi?.title {
                    fullInfo = #"{"application": "\#(currentAppName)", "metadata": "\#(ft)"}"#
                } else {
                    fullInfo = #"{"application": "\#(currentAppName)}"#
                }

                (fullInfo + "\n").withCString { cstr in
                    _ = write(clientFD, cstr, strlen(cstr))
                }

                close(clientFD)
            }
        }

        RunLoop.main.run()
    }
    
    static func getFocusedApp() -> String {
        let app = NSWorkspace.shared.frontmostApplication
        let name = app?.localizedName ?? "Unknown"

        return name + "\n"
    }
    
    static func setupSocket(serverFD: Int32) {
        let socketPath = "/tmp/appdetect.sock"

        // Remove any existing socket
        unlink(socketPath)

        // sockaddr_un
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        _ = socketPath.withCString { cstr in
            strncpy(&addr.sun_path.0, cstr, MemoryLayout.size(ofValue: addr.sun_path))
        }

        let len = socklen_t(
            MemoryLayout.size(ofValue: addr.sun_family) +
            socketPath.utf8.count + 1
        )

        // Bind
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverFD, $0, len)
            }
        }
        guard bindResult == 0 else {
            perror("bind")
            exit(1)
        }

        // Listen
        guard listen(serverFD, 8) == 0 else {
            perror("listen")
            exit(1)
        }

        print("Listening on \(socketPath)")
    }
}
