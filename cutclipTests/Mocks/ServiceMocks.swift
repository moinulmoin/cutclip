//
//  ServiceMocks.swift
//  cutclipTests
//
//  Mock implementations of core services for testing
//

import Foundation
@testable import cutclip

// MARK: - Mock BinaryManager

@MainActor
class MockBinaryManager: BinaryManager {
    var mockYtDlpPath: String? = "/mock/yt-dlp"
    var mockFfmpegPath: String? = "/mock/ffmpeg"
    var mockIsConfigured = true
    var mockVerificationResults: [BinaryType: Bool] = [:]
    var verifyBinaryCalled = false
    var verifyAllBinariesCalled = false
    
    override init() {
        super.init()
        self.ytDlpPath = mockYtDlpPath
        self.ffmpegPath = mockFfmpegPath
        self.isConfigured = mockIsConfigured
    }
    
    override func verifyBinary(_ binary: BinaryType) async -> Bool {
        verifyBinaryCalled = true
        return mockVerificationResults[binary] ?? true
    }
    
    override func verifyAllBinaries() async -> Bool {
        verifyAllBinariesCalled = true
        return mockVerificationResults.values.allSatisfy { $0 }
    }
}

// MARK: - Mock ErrorHandler

@MainActor
class MockErrorHandler: ErrorHandler {
    var handledErrors: [(Error, ErrorContext)] = []
    var presentedAlerts: [(title: String, message: String)] = []
    
    override func handle(_ error: Error, context: ErrorContext) {
        handledErrors.append((error, context))
        super.handle(error, context: context)
    }
    
    override func presentAlert(title: String, message: String, actions: [ErrorAction]) {
        presentedAlerts.append((title: title, message: message))
    }
}

// MARK: - Mock LicenseManager

@MainActor
class MockLicenseManager: LicenseManager {
    var mockHasValidLicense = false
    var mockCanUseApp = true
    var mockLicenseKey: String?
    var mockLicenseEmail: String?
    var activateLicenseCalled = false
    var restoreLicenseCalled = false
    
    override init() {
        // Initialize with mock error handler and state manager
        let errorHandler = LicenseErrorHandler(errorHandler: MockErrorHandler.shared)
        let stateManager = LicenseStateManager()
        let analyticsService = LicenseAnalyticsService()
        
        super.init(
            licenseErrorHandler: errorHandler,
            licenseStateManager: stateManager,
            licenseAnalyticsService: analyticsService
        )
        
        self.hasValidLicense = mockHasValidLicense
        self.canUseApp = mockCanUseApp
        self.licenseKey = mockLicenseKey
        self.licenseEmail = mockLicenseEmail
    }
    
    override func activateLicense(withKey key: String) async -> Bool {
        activateLicenseCalled = true
        if mockHasValidLicense {
            self.licenseKey = key
            self.hasValidLicense = true
            return true
        }
        return false
    }
    
    override func restoreLicense() async {
        restoreLicenseCalled = true
        if let key = mockLicenseKey {
            self.licenseKey = key
            self.hasValidLicense = mockHasValidLicense
        }
    }
}

// MARK: - Mock UsageTracker

@MainActor
class MockUsageTracker: UsageTracker {
    var mockDeviceId = "mock-device-123"
    var mockFreeCredits = 5
    var mockIsActive = true
    var mockCheckDeviceResponse: DeviceStatusResponse?
    var mockError: Error?
    
    var checkDeviceStatusCalled = false
    var createDeviceCalled = false
    var decrementCreditsCalled = false
    var validateLicenseCalled = false
    
    override init() {
        // Create mock dependencies
        let cacheService = CacheService()
        let apiClient = APIClient()
        let deviceRepo = DeviceRepository(apiClient: apiClient, cacheService: cacheService)
        let licenseRepo = LicenseRepository(apiClient: apiClient, cacheService: cacheService)
        
        super.init(
            cacheService: cacheService,
            apiClient: apiClient,
            deviceRepository: deviceRepo,
            licenseRepository: licenseRepo
        )
        
        self.deviceId = mockDeviceId
        self.freeCredits = mockFreeCredits
        self.isActive = mockIsActive
    }
    
    override func checkDeviceStatus(forceRefresh: Bool = false) async throws {
        checkDeviceStatusCalled = true
        
        if let error = mockError {
            throw error
        }
        
        // Update state based on mock values
        self.freeCredits = mockFreeCredits
        self.isActive = mockIsActive
        
        if let response = mockCheckDeviceResponse {
            self.deviceId = response.id
            self.freeCredits = response.freeCredits
            self.isActive = response.isActive
        }
    }
    
    override func createDevice() async throws {
        createDeviceCalled = true
        
        if let error = mockError {
            throw error
        }
        
        // Simulate successful device creation
        self.freeCredits = 5
        self.isActive = true
    }
    
    override func decrementFreeCredits() async throws {
        decrementCreditsCalled = true
        
        if let error = mockError {
            throw error
        }
        
        if freeCredits > 0 {
            freeCredits -= 1
        }
    }
    
    override func validateLicense(_ key: String) async throws -> Bool {
        validateLicenseCalled = true
        
        if let error = mockError {
            throw error
        }
        
        // Simple mock validation
        return key.hasPrefix("VALID-")
    }
}

// MARK: - Mock ProcessExecutor

class MockProcessExecutor: ProcessExecutor {
    var mockResults: [String: ProcessResult] = [:]
    var mockErrors: [String: Error] = [:]
    var executeCalled: [(path: String, args: [String])] = []
    var defaultResult = ProcessResult(exitCode: 0, output: Data(), error: Data(), duration: 0.1)
    
    override func execute(_ config: ProcessConfiguration) async throws -> ProcessResult {
        let key = "\(config.executablePath):\(config.arguments.joined(separator: ","))"
        executeCalled.append((path: config.executablePath, args: config.arguments))
        
        // Check for mock error
        if let error = mockErrors[key] {
            throw error
        }
        
        // Check for mock result
        if let result = mockResults[key] {
            // Call handlers if provided
            if let outputHandler = config.outputHandler,
               let outputString = result.outputString {
                outputHandler(outputString)
            }
            
            if let errorHandler = config.errorHandler,
               let errorString = result.errorString {
                errorHandler(errorString)
            }
            
            return result
        }
        
        // Return default result
        return defaultResult
    }
    
    func addMockResult(
        for executable: String,
        args: [String],
        exitCode: Int32 = 0,
        output: String = "",
        error: String = "",
        duration: TimeInterval = 0.1
    ) {
        let key = "\(executable):\(args.joined(separator: ","))"
        mockResults[key] = ProcessResult(
            exitCode: exitCode,
            output: output.data(using: .utf8) ?? Data(),
            error: error.data(using: .utf8) ?? Data(),
            duration: duration
        )
    }
    
    func addMockError(
        for executable: String,
        args: [String],
        error: Error
    ) {
        let key = "\(executable):\(args.joined(separator: ","))"
        mockErrors[key] = error
    }
}

// MARK: - Mock DownloadService

@MainActor
class MockDownloadService: DownloadService {
    var mockDownloadPath = "/tmp/mock-video.mp4"
    var mockError: Error?
    var downloadVideoCalled = false
    var lastDownloadJob: ClipJob?
    
    override func downloadVideo(for job: ClipJob) async throws -> String {
        downloadVideoCalled = true
        lastDownloadJob = job
        
        if let error = mockError {
            throw error
        }
        
        return mockDownloadPath
    }
    
    override func isValidYouTubeURL(_ urlString: String) -> Bool {
        // Simple mock validation
        return urlString.contains("youtube.com") || urlString.contains("youtu.be")
    }
}

// MARK: - Mock VideoInfoService

@MainActor
class MockVideoInfoService: VideoInfoService {
    var mockVideoInfo: VideoInfo?
    var mockError: Error?
    var fetchInfoCalled = false
    var lastFetchedURL: String?
    
    override func fetchVideoInfo(from url: String) async throws -> VideoInfo {
        fetchInfoCalled = true
        lastFetchedURL = url
        
        if let error = mockError {
            throw error
        }
        
        return mockVideoInfo ?? TestDataBuilder.makeVideoInfo()
    }
}

// MARK: - Mock ClipService

@MainActor
class MockClipService: ClipService {
    var mockError: Error?
    var processJobCalled = false
    var lastProcessedJob: ClipJob?
    var mockOutputPath = "/tmp/output.mp4"
    
    override func processJob(_ job: ClipJob) async throws -> ClipJob {
        processJobCalled = true
        lastProcessedJob = job
        
        if let error = mockError {
            throw error
        }
        
        var completedJob = job
        completedJob.status = .completed
        completedJob.outputFilePath = mockOutputPath
        completedJob.progress = 1.0
        
        return completedJob
    }
}