import OSLog

enum Log {
    static let subsystem = "it.typeme.typemeit"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let shortcuts = Logger(subsystem: subsystem, category: "shortcuts")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let transcriber = Logger(subsystem: subsystem, category: "transcriber")
    static let postProcess = Logger(subsystem: subsystem, category: "postprocess")
    static let output = Logger(subsystem: subsystem, category: "output")
    static let learning = Logger(subsystem: subsystem, category: "learning")
    static let store = Logger(subsystem: subsystem, category: "store")
    static let model = Logger(subsystem: subsystem, category: "model")
    static let updates = Logger(subsystem: subsystem, category: "updates")
}
