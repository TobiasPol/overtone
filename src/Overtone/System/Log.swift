import os

/// Unified logging. Watch with:
/// `log stream --predicate 'subsystem == "com.tobiaspol.overtone"' --level debug`
enum Log {
    static let engine = Logger(subsystem: "com.tobiaspol.overtone", category: "engine")
    static let plugins = Logger(subsystem: "com.tobiaspol.overtone", category: "plugins")
    static let detection = Logger(subsystem: "com.tobiaspol.overtone", category: "detection")
}
