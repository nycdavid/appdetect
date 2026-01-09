// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import AppKit

@main
struct appdetect {
    static func main() {
        // 1. listen on a socket
        // 2. request handling
        //  - request comes in -> focused app is queried
        //  - app information + metadata (as JSON) is returned via socket
        //
        
        // Create UNIX socket
        let serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            perror("socket")
            exit(1)
        }
        defer { close(serverFD) }
        
        // Set up socket for listening
        setupSocket(serverFD: serverFD)

        // Accept loop
        while true {
            let clientFD = accept(serverFD, nil, nil)
            if clientFD < 0 {
                perror("accept")
                continue
            }

            let response = getFocusedApp()
            response.withCString { cstr in
                _ = write(clientFD, cstr, strlen(cstr))
            }

            close(clientFD)
        }
    }
    
    static func getFocusedApp() -> String {
        return "Hello from appdetect\n"
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
