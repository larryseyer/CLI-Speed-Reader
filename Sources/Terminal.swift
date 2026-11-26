import AppKit

enum Terminal {
    static func run(_ body: String) throws -> NSAppleEventDescriptor {
        let source = """
        with timeout of 3 seconds
            tell application id "com.apple.Terminal"
                \(body)
            end tell
        end timeout
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw NSError(domain: "RSVP", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not compile Terminal reader."])
        }
        let result = script.executeAndReturnError(&error)
        if let error {
            let number = error[NSAppleScript.errorNumber] as? Int ?? 0
            let message = number == -1743
                ? "Allow CLI Speed Reader → Terminal in System Settings → Privacy & Security → Automation, then try again."
                : error[NSAppleScript.errorMessage] as? String ?? "Terminal is unavailable."
            throw NSError(domain: "RSVP", code: number, userInfo: [NSLocalizedDescriptionKey: message])
        }
        return result
    }

    static func bind() throws -> (String, String) {
        let result = try run("""
        if (count of windows) is 0 then error "Open a Terminal window first."
        set t to selected tab of front window
        return {tty of t, contents of t}
        """)
        guard let tty = result.atIndex(1)?.stringValue,
              tty.range(of: #"^/dev/[A-Za-z0-9._/-]+$"#, options: .regularExpression) != nil,
              let text = result.atIndex(2)?.stringValue else {
            throw NSError(domain: "RSVP", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not identify the Terminal tab."])
        }
        return (tty, text)
    }

    static func contents(tty: String) throws -> String {
        try run("""
        repeat with w in windows
            repeat with t in tabs of w
                if tty of t is "\(tty)" then return contents of t
            end repeat
        end repeat
        error "The watched Terminal tab was closed. Choose another tab."
        """).stringValue ?? ""
    }
}
