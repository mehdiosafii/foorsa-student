// Foorsa-local policy. Called before any Foorsa* message is dispatched to Dart.
enum FoorsaBridgePolicy {
    static func allows(isMainFrame: Bool, scheme: String, host: String, port: Int) -> Bool {
        return isMainFrame && scheme == "https" && host == "student.foorsa.ma"
            && (port == 0 || port == 443)
    }
}
