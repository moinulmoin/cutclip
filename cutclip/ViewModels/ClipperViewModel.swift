//
//  ClipperViewModel.swift
//  cutclip
//
//  Created by Moinul Moin on 7/1/25.
//

import SwiftUI
import Combine

@MainActor
final class ClipperViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var urlText = ""
    @Published var urlValidationError: String? = nil
    @Published var startTime = "00:00:00"
    @Published var endTime = "00:00:10"
    @Published var selectedQuality = "720p"
    @Published var selectedAspectRatio = ClipJob.AspectRatio.original
    
    // Processing State
    @Published var isProcessing = false
    @Published var processingProgress: Double = 0.0
    @Published var processingMessage = "Starting..."
    @Published var completedVideoPath: String?
    @Published var showingLicenseView = false
    
    // Video Info Loading
    @Published var isLoadingVideoInfo = false
    @Published var loadedVideoInfo: VideoInfo?
    
    // Completion State
    @Published var showCompletionView = false
    @Published var savedVideoURL = ""
    
    // MARK: - Services
    private var binaryManager: BinaryManager
    private var errorHandler: ErrorHandler
    private var licenseManager: LicenseManager
    private var usageTracker: UsageTracker
    private let networkMonitor = NetworkMonitor.shared
    private var videoInfoService: VideoInfoService?
    
    // MARK: - Task Management
    private var videoInfoLoadingTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?
    
    // MARK: - Constants
    let qualityOptions = ["720p", "1080p", "1440p", "2160p"]
    let aspectRatioOptions: [ClipJob.AspectRatio] = [.original, .nineSixteen, .oneOne, .fourThree]
    
    // MARK: - Computed Properties
    var canCreateClip: Bool {
        !urlText.isEmpty && loadedVideoInfo != nil && !isProcessing && !isLoadingVideoInfo
    }
    
    var canLoadVideoInfo: Bool {
        !urlText.isEmpty && !isProcessing && !isLoadingVideoInfo && urlValidationError == nil
    }
    
    var hasLoadedVideo: Bool {
        loadedVideoInfo != nil
    }
    
    // MARK: - Initialization
    init(
        binaryManager: BinaryManager,
        errorHandler: ErrorHandler,
        licenseManager: LicenseManager,
        usageTracker: UsageTracker
    ) {
        self.binaryManager = binaryManager
        self.errorHandler = errorHandler
        self.licenseManager = licenseManager
        self.usageTracker = usageTracker
        
        setupVideoInfoService()
    }
    
    deinit {
        // Tasks are automatically cancelled when their references are released
        // No need to explicitly cancel them in deinit
    }
    
    // MARK: - Setup
    func setupVideoInfoService() {
        videoInfoService = VideoInfoService(binaryManager: binaryManager)
    }
    
    func updateDependencies(
        binaryManager: BinaryManager,
        errorHandler: ErrorHandler,
        licenseManager: LicenseManager,
        usageTracker: UsageTracker
    ) {
        self.binaryManager = binaryManager
        self.errorHandler = errorHandler
        self.licenseManager = licenseManager
        self.usageTracker = usageTracker
    }
    
    // MARK: - Public Methods
    
    func loadVideoInfo() {
        guard !urlText.isEmpty else { return }
        
        // Validate URL before attempting to load
        guard ValidationUtils.isValidYouTubeURL(urlText) else {
            urlValidationError = "Please enter a valid YouTube URL"
            return
        }
        
        guard let service = videoInfoService else { return }
        
        // Cancel any existing loading task
        videoInfoLoadingTask?.cancel()
        
        videoInfoLoadingTask = Task {
            // Show loading while binaries initialize (only first time)
            if !binaryManager.areBinariesReady {
                await MainActor.run {
                    self.isLoadingVideoInfo = true
                }
                await binaryManager.ensureBinariesReady()
            }
            
            await performVideoInfoLoad(service: service)
            await MainActor.run {
                self.videoInfoLoadingTask = nil
            }
        }
    }
    
    func clearVideoInfo() {
        loadedVideoInfo = nil
        // Reset quality selection to default when clearing
        if !qualityOptions.contains(selectedQuality) {
            selectedQuality = "720p"
        }
    }
    
    func processVideo() {
        // Cancel any existing processing task
        processingTask?.cancel()
        
        processingTask = Task {
            await performVideoProcessing()
            await MainActor.run {
                self.processingTask = nil
            }
        }
    }
    
    func openVideo(at path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }
    
    func showInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    func resetState() {
        urlText = ""
        urlValidationError = nil
        startTime = "00:00:00"
        endTime = "00:00:10"
        selectedQuality = "720p"
        selectedAspectRatio = .original
        isProcessing = false
        processingProgress = 0.0
        processingMessage = "Starting..."
        completedVideoPath = nil
        loadedVideoInfo = nil
        showCompletionView = false
        savedVideoURL = ""
        
        // Cancel any running tasks
        cancelAllTasks()
    }
    
    func continueWithSameVideo() {
        // Keep the same video loaded but reset clip settings
        completedVideoPath = nil
        processingProgress = 0.0
        processingMessage = "Starting..."
        startTime = "00:00:00"
        endTime = "00:00:10"
        showCompletionView = false
        // Keep the loaded video info and URL
        urlText = savedVideoURL
    }
    
    func showLicenseView() {
        showingLicenseView = true
    }
    
    func onURLChange() {
        clearVideoInfo()
        validateURL()
    }
    
    private func validateURL() {
        // Clear error if URL is empty
        guard !urlText.isEmpty else {
            urlValidationError = nil
            return
        }
        
        // Validate YouTube URL format
        if ValidationUtils.isValidYouTubeURL(urlText) {
            urlValidationError = nil
        } else {
            urlValidationError = "Please enter a valid YouTube URL (e.g., youtube.com/watch?v=...)"
        }
    }
    
    // MARK: - Private Methods
    
    private func performVideoInfoLoad(service: VideoInfoService) async {
        isLoadingVideoInfo = true
        defer {
            isLoadingVideoInfo = false
        }
        
        do {
            let videoInfo = try await service.loadVideoInfo(for: urlText)
            
            // Validate the loaded video info
            guard ValidationUtils.isValidVideoInfo(videoInfo) else {
                throw VideoInfoError.parsingFailed("Invalid video information received")
            }
            
            loadedVideoInfo = videoInfo
            
            // Update quality selection if current selection is not available
            if !videoInfo.qualityOptions.contains(selectedQuality) {
                selectedQuality = videoInfo.qualityOptions.first ?? "Best"
            }
            
        } catch let error as VideoInfoError {
            await MainActor.run {
                errorHandler.handle(error.toAppError())
            }
        } catch {
            await MainActor.run {
                errorHandler.handle(AppError.unknown("Failed to load video information: \(error.localizedDescription)"))
            }
        }
    }
    
    private func performVideoProcessing() async {
        // Show progress immediately
        isProcessing = true
        processingProgress = 0.0
        processingMessage = "Starting..."
        completedVideoPath = nil
        showCompletionView = false
        
        defer {
            // Always hide processing state when done
            isProcessing = false
            print("🎬 Processing complete. isProcessing: false, showCompletionView: \(showCompletionView)")
        }
        
        do {
            // Check license and usage first
            try await checkLicenseAndUsage()
            
            // Ensure binaries are ready (lazy initialization)
            if !binaryManager.areBinariesReady {
                processingMessage = "Initializing tools..."
                await binaryManager.ensureBinariesReady()
            }
            
            // Validate inputs
            try await validateInputs()
            
            // Check network connectivity
            try await checkNetworkConnectivity()
            
            // Check disk space
            try await checkDiskSpace()
            
            // Validate quality selection
            try await validateQualitySelection()
            
            // Create clip job
            let job = createClipJob()
            
            // Initialize services
            let (downloadSvc, clipSvc) = await initializeServices()
            
            // Download video
            let downloadedPath = try await downloadVideo(job: job, service: downloadSvc)
            
            // Clip video
            let outputPath = try await clipVideo(
                inputPath: downloadedPath,
                job: job,
                service: clipSvc
            )
            
            // Record usage
            try await recordUsage()
            
            // Success!
            await handleSuccess(outputPath: outputPath)
            
        } catch let error as DownloadError {
            await MainActor.run {
                errorHandler.handle(error.toAppError())
            }
        } catch let error as ClipError {
            await MainActor.run {
                errorHandler.handle(error.toAppError())
            }
        } catch let error as UsageError {
            await MainActor.run {
                errorHandler.handle(AppError.licenseError(error.localizedDescription))
            }
        } catch let error as AppError {
            await MainActor.run {
                errorHandler.handle(error)
            }
        } catch {
            await MainActor.run {
                errorHandler.handle(AppError.unknown("Processing failed: \(error.localizedDescription)"))
            }
        }
    }
    
    // MARK: - Processing Steps
    
    private func checkLicenseAndUsage() async throws {
        processingMessage = "Checking license..."
        processingProgress = 0.05
        
        guard usageTracker.canUseApp() else {
            throw AppError.licenseError("No remaining uses. License required to continue.")
        }
    }
    
    private func validateInputs() async throws {
        processingMessage = "Validating inputs..."
        processingProgress = 0.1
        
        guard ValidationUtils.isValidYouTubeURL(urlText) else {
            throw AppError.invalidInput("Please enter a valid YouTube URL")
        }
        
        guard ValidationUtils.isValidTimeFormat(startTime) && ValidationUtils.isValidTimeFormat(endTime) else {
            throw AppError.invalidInput("Please enter valid time formats (HH:MM:SS)")
        }
        
        guard ValidationUtils.isValidTimeRange(start: startTime, end: endTime) else {
            throw AppError.invalidInput("Start time must be before end time")
        }
    }
    
    private func checkNetworkConnectivity() async throws {
        processingMessage = "Checking network..."
        processingProgress = 0.2
        
        guard networkMonitor.requireNetwork() else {
            throw AppError.network("No internet connection. Please check your network settings.")
        }
    }
    
    private func checkDiskSpace() async throws {
        processingMessage = "Checking disk space..."
        processingProgress = 0.3
        
        try ErrorHandler.checkDiskSpace()
    }
    
    private func validateQualitySelection() async throws {
        processingMessage = "Validating quality..."
        processingProgress = 0.35
        
        if let videoInfo = loadedVideoInfo {
            guard ValidationUtils.isValidQualityForVideoInfo(selectedQuality, videoInfo: videoInfo) else {
                throw AppError.invalidInput("Selected quality '\(selectedQuality)' is not available for this video. Available qualities: \(videoInfo.qualityOptions.joined(separator: ", "))")
            }
        }
    }
    
    private func createClipJob() -> ClipJob {
        ClipJob(
            url: urlText,
            startTime: startTime,
            endTime: endTime,
            aspectRatio: selectedAspectRatio,
            quality: selectedQuality,
            videoInfo: loadedVideoInfo
        )
    }
    
    private func initializeServices() async -> (DownloadService, ClipService) {
        processingMessage = "Initializing services..."
        processingProgress = 0.4
        
        let downloadSvc = DownloadService(binaryManager: binaryManager)
        let clipSvc = ClipService(binaryManager: binaryManager)
        
        return (downloadSvc, clipSvc)
    }
    
    private func downloadVideo(job: ClipJob, service: DownloadService) async throws -> String {
        processingMessage = "Downloading video..."
        processingProgress = 0.5
        
        // Track this download for safety monitoring
        await MainActor.run {
            usageTracker.trackDownload()
        }
        
        return try await service.downloadVideo(for: job)
    }
    
    private func clipVideo(inputPath: String, job: ClipJob, service: ClipService) async throws -> String {
        processingMessage = "Processing video..."
        processingProgress = 0.7
        
        return try await service.clipVideo(inputPath: inputPath, job: job)
    }
    
    private func recordUsage() async throws {
        processingMessage = "Recording usage..."
        processingProgress = 0.9
        
        try await usageTracker.decrementCredits()
        
        // Force UI refresh after credit decrement
        await licenseManager.refreshLicenseStatus()
    }
    
    private func handleSuccess(outputPath: String) async {
        await MainActor.run {
            self.completedVideoPath = outputPath
            self.processingProgress = 1.0
            self.processingMessage = "Complete!"
            self.showCompletionView = true
            self.savedVideoURL = urlText
            print("🎬 Clip completed! showCompletionView: \(self.showCompletionView), path: \(outputPath)")
        }
    }
    
    func cancelProcessing() {
        cancelAllTasks()
        // Reset processing state
        isProcessing = false
        processingProgress = 0.0
        processingMessage = "Cancelled"
        // Show a temporary message before clearing
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            await MainActor.run {
                self.processingMessage = "Starting..."
            }
        }
    }
    
    private func cancelAllTasks() {
        videoInfoLoadingTask?.cancel()
        processingTask?.cancel()
    }
}