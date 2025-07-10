//
//  LoggingService.swift
//  cutclip
//
//  Created by Moinul Moin on 7/9/25.
//

import Foundation
import os
import AppKit

/// Minimal logging service for CutClip
/// Uses os.log for system integration and writes critical logs to file
final class LoggingService: @unchecked Sendable {
    static let shared = LoggingService()
    
    private let logger = Logger(subsystem: "com.ideaplexa.cutclip", category: "general")
    private let logFileURL: URL
    private let crashMarkerURL: URL
    private let fileHandle: FileHandle?
    private let dateFormatter: DateFormatter
    private let queue = DispatchQueue(label: "com.ideaplexa.cutclip.logging", qos: .utility)
    
    private init() {
        // Setup log file
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/CutClip")
        logFileURL = logsDir.appendingPathComponent("cutclip.log")
        crashMarkerURL = FileManager.default.temporaryDirectory.appendingPathComponent("cutclip.running")
        
        // Create directory
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        
        // Setup date formatter
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        
        // Open file handle for appending
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: logFileURL)
        fileHandle?.seekToEndOfFile()
        
        // Check for previous crash
        if FileManager.default.fileExists(atPath: crashMarkerURL.path) {
            error("App crashed on previous run", category: "crash")
            try? FileManager.default.removeItem(at: crashMarkerURL)
        }
        
        // Create crash marker
        FileManager.default.createFile(atPath: crashMarkerURL.path, contents: nil)
        
        // Remove marker on clean exit
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            try? FileManager.default.removeItem(at: self.crashMarkerURL)
        }
    }
    
    deinit {
        fileHandle?.closeFile()
    }
    
    // MARK: - Public Methods
    
    func debug(_ message: String, category: String = "general") {
        logger.debug("\(message, privacy: .public)")
        writeToFile("[DEBUG] [\(category)] \(message)")
    }
    
    func info(_ message: String, category: String = "general") {
        logger.info("\(message, privacy: .public)")
        writeToFile("[INFO] [\(category)] \(message)")
    }
    
    func warning(_ message: String, category: String = "general") {
        logger.warning("\(message, privacy: .public)")
        writeToFile("[WARNING] [\(category)] \(message)")
    }
    
    func error(_ message: String, category: String = "general", error: Error? = nil) {
        var fullMessage = message
        if let error = error {
            fullMessage += " - \(error.localizedDescription)"
        }
        logger.error("\(fullMessage, privacy: .public)")
        writeToFile("[ERROR] [\(category)] \(fullMessage)")
    }
    
    func critical(_ message: String, error: Error? = nil) {
        var fullMessage = message
        if let error = error {
            fullMessage += " - \(error)"
        }
        logger.critical("\(fullMessage, privacy: .public)")
        writeToFile("[CRITICAL] \(fullMessage)")
        
        // Force sync for critical errors
        fileHandle?.synchronizeFile()
    }
    
    // MARK: - Private Methods
    
    private func writeToFile(_ message: String) {
        queue.async { [weak self] in
            guard let self = self, let fileHandle = self.fileHandle else { return }
            
            let timestamp = self.dateFormatter.string(from: Date())
            let logEntry = "[\(timestamp)] \(message)\n"
            
            if let data = logEntry.data(using: .utf8) {
                fileHandle.write(data)
            }
        }
    }
    
    
    // MARK: - Public Utilities
    
    func getLogFileURL() -> URL {
        return logFileURL
    }
    
    func flush() {
        fileHandle?.synchronizeFile()
    }
}