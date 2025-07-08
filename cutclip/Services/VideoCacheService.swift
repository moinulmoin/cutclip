//
//  VideoCacheService.swift
//  cutclip
//
//  Created by Assistant on 7/7/25.
//

import Foundation
import CryptoKit

/// Metadata for a cached video file
struct CachedVideo: Codable {
    let videoId: String
    let quality: String
    let filePath: String
    let cachedAt: Date
    let expiresAt: Date
    let fileSize: Int64
    let videoInfo: VideoInfo
}

/// Service for managing cached video downloads
@MainActor
class VideoCacheService: ObservableObject {
    @Published var totalCacheSize: Int64 = 0
    @Published var isCacheEnabled: Bool = true
    
    private let cacheDirectory: URL
    private let videosDirectory: URL
    private let indexFile: URL
    private var cacheIndex: [String: CachedVideo] = [:]
    
    // Configuration
    private let cacheDuration: TimeInterval = 86400 // 24 hours
    private let maxCacheSize: Int64 = 5 * 1024 * 1024 * 1024 // 5GB
    private let maxCacheEntries: Int = 1000 // Maximum number of cached videos
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheDirectory = appSupport.appendingPathComponent("CutClip/cache")
        videosDirectory = cacheDirectory.appendingPathComponent("videos")
        indexFile = cacheDirectory.appendingPathComponent("cache_index.json")
        
        // Create directories if they don't exist
        try? FileManager.default.createDirectory(at: videosDirectory, withIntermediateDirectories: true)
        
        // Load cache index
        loadCacheIndex()
        
        // Clean expired entries on init (after index is loaded)
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s delay to ensure index is loaded
            await cleanExpiredCache()
        }
    }
    
    // MARK: - Public Methods
    
    /// Check if a video is cached and still valid
    func checkCache(videoId: String?, quality: String) -> CachedVideo? {
        guard isCacheEnabled, let videoId = videoId else { return nil }
        
        let cacheKey = generateCacheKey(videoId: videoId, quality: quality)
        guard let cached = cacheIndex[cacheKey] else { return nil }
        
        // Check if expired
        if cached.expiresAt < Date() {
            // Remove expired entry
            removeCacheEntry(cacheKey: cacheKey)
            return nil
        }
        
        // Check if file still exists and is readable
        let fileURL = URL(fileURLWithPath: cached.filePath)
        do {
            let isReachable = try fileURL.checkResourceIsReachable()
            if !isReachable {
                // Remove invalid entry
                removeCacheEntry(cacheKey: cacheKey)
                return nil
            }
        } catch {
            // File not accessible, remove entry
            print("⚠️ Cache file not accessible: \(error)")
            removeCacheEntry(cacheKey: cacheKey)
            return nil
        }
        
        print("📦 Cache hit for video \(videoId) at \(quality)")
        return cached
    }
    
    /// Save a downloaded video to cache
    /// - Returns: Boolean indicating whether caching was successful
    func saveToCache(videoPath: String, videoInfo: VideoInfo?, quality: String) -> Bool {
        guard isCacheEnabled, let videoInfo = videoInfo else { return false }
        
        let cacheKey = generateCacheKey(videoId: videoInfo.id, quality: quality)
        let videoDirectory = videosDirectory.appendingPathComponent("\(videoInfo.id)_\(quality)")
        
        do {
            // Create video-specific directory
            try FileManager.default.createDirectory(at: videoDirectory, withIntermediateDirectories: true)
            
            // Determine file extension
            let sourceURL = URL(fileURLWithPath: videoPath)
            let fileExtension = sourceURL.pathExtension.isEmpty ? "mp4" : sourceURL.pathExtension
            let destinationURL = videoDirectory.appendingPathComponent("video.\(fileExtension)")
            
            // Copy file to cache (don't move to avoid losing the original)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            
            // Get file size
            let attributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
            let fileSize = attributes[FileAttributeKey.size] as? Int64 ?? 0
            
            // Create cache entry
            let cached = CachedVideo(
                videoId: videoInfo.id,
                quality: quality,
                filePath: destinationURL.path,
                cachedAt: Date(),
                expiresAt: Date().addingTimeInterval(cacheDuration),
                fileSize: fileSize,
                videoInfo: videoInfo
            )
            
            // Update index
            cacheIndex[cacheKey] = cached
            saveCacheIndex()
            updateCacheSize()
            
            print("📦 Cached video \(videoInfo.id) at \(quality) (\(formatBytes(fileSize)))")
            
            // Check if we need to clean up due to size or entry limits
            Task {
                await enforceMaxCacheSize()
                await enforceMaxEntries()
            }
            
            return true
            
        } catch {
            print("❌ Failed to cache video: \(error)")
            return false
        }
    }
    
    /// Remove expired cache entries
    func cleanExpiredCache() async {
        print("🧹 Cleaning expired cache entries...")
        
        let now = Date()
        var removedCount = 0
        
        for (key, cached) in cacheIndex {
            if cached.expiresAt < now {
                removeCacheEntry(cacheKey: key)
                removedCount += 1
            }
        }
        
        if removedCount > 0 {
            print("🧹 Removed \(removedCount) expired cache entries")
            saveCacheIndex()
            updateCacheSize()
        }
    }
    
    /// Clear all cache
    func clearCache() {
        print("🗑️ Clearing entire cache...")
        
        // Remove all video files
        try? FileManager.default.removeItem(at: videosDirectory)
        try? FileManager.default.createDirectory(at: videosDirectory, withIntermediateDirectories: true)
        
        // Clear index
        cacheIndex.removeAll()
        saveCacheIndex()
        totalCacheSize = 0
    }
    
    /// Remove a specific cached video
    func removeCachedVideo(videoId: String?, quality: String) {
        guard let videoId = videoId else { return }
        
        let cacheKey = generateCacheKey(videoId: videoId, quality: quality)
        if cacheIndex[cacheKey] != nil {
            print("🗑️ Removing cached video \(videoId) at \(quality)")
            removeCacheEntry(cacheKey: cacheKey)
            saveCacheIndex()
            updateCacheSize()
        }
    }
    
    /// Get human-readable cache size
    var formattedCacheSize: String {
        formatBytes(totalCacheSize)
    }
    
    // MARK: - Private Methods
    
    private func generateCacheKey(videoId: String, quality: String) -> String {
        let combined = "\(videoId)_\(quality)"
        let hash = SHA256.hash(data: Data(combined.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func loadCacheIndex() {
        Task { @MainActor in
            guard FileManager.default.fileExists(atPath: indexFile.path) else { return }
            
            do {
                let data = try Data(contentsOf: indexFile)
                cacheIndex = try JSONDecoder().decode([String: CachedVideo].self, from: data)
                updateCacheSize()
            } catch {
                print("⚠️ Failed to load cache index: \(error)")
                cacheIndex = [:]
            }
        }
    }
    
    private func saveCacheIndex() {
        Task { @MainActor in
            do {
                let data = try JSONEncoder().encode(cacheIndex)
                try data.write(to: indexFile)
            } catch {
                print("❌ Failed to save cache index: \(error)")
            }
        }
    }
    
    private func removeCacheEntry(cacheKey: String) {
        guard let cached = cacheIndex[cacheKey] else { return }
        
        // Remove video file
        let videoDirectory = URL(fileURLWithPath: cached.filePath).deletingLastPathComponent()
        do {
            try FileManager.default.removeItem(at: videoDirectory)
        } catch {
            print("⚠️ Failed to remove cache directory: \(error)")
        }
        
        // Remove from index
        cacheIndex.removeValue(forKey: cacheKey)
    }
    
    private func updateCacheSize() {
        totalCacheSize = cacheIndex.values.reduce(0) { $0 + $1.fileSize }
    }
    
    private func enforceMaxCacheSize() async {
        guard totalCacheSize > maxCacheSize else { return }
        
        print("⚠️ Cache size (\(formatBytes(totalCacheSize))) exceeds limit (\(formatBytes(maxCacheSize)))")
        
        // Sort by cached date (oldest first)
        let sortedEntries = cacheIndex.sorted { $0.value.cachedAt < $1.value.cachedAt }
        
        // Remove oldest entries until under limit
        for (key, _) in sortedEntries {
            if totalCacheSize <= maxCacheSize { break }
            removeCacheEntry(cacheKey: key)
            updateCacheSize()
        }
        
        saveCacheIndex()
        print("✅ Cache size reduced to \(formatBytes(totalCacheSize))")
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func enforceMaxEntries() async {
        guard cacheIndex.count > maxCacheEntries else { return }
        
        print("⚠️ Cache entries (\(cacheIndex.count)) exceed limit (\(maxCacheEntries))")
        
        // Sort by cached date (oldest first)
        let sortedEntries = cacheIndex.sorted { $0.value.cachedAt < $1.value.cachedAt }
        
        // Remove oldest entries until under limit
        let entriesToRemove = cacheIndex.count - maxCacheEntries
        for (index, (key, _)) in sortedEntries.enumerated() {
            if index >= entriesToRemove { break }
            removeCacheEntry(cacheKey: key)
        }
        
        saveCacheIndex()
        updateCacheSize()
        print("✅ Cache entries reduced to \(cacheIndex.count)")
    }
}

