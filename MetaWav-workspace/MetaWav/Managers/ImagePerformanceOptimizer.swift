// ImagePerformanceOptimizer.swift - Fixes image processing performance issues
import Foundation
import AppKit
import SwiftUI
import Combine

class ImagePerformanceOptimizer: ObservableObject {
    static let shared = ImagePerformanceOptimizer()
    
    // Image processing queues
    private let imageProcessingQueue = DispatchQueue(label: "image.processing", qos: .userInitiated)
    private let imageCacheQueue = DispatchQueue(label: "image.cache", qos: .utility)
    
    // Smart caching system
    private let imageCache = NSCache<NSString, NSImage>()
    private let thumbnailCache = NSCache<NSString, NSImage>()
    
    // Performance monitoring
    @Published var isProcessing = false
    @Published var processingQueueSize = 0
    @Published var cacheHitRate: Double = 0.0
    
    // Statistics
    private var totalRequests = 0
    private var cacheHits = 0
    private var processingTimes: [TimeInterval] = []
    
    private init() {
        setupCache()
        print("🖼️ ImagePerformanceOptimizer initialized")
    }
    
    // MARK: - Cache Setup
    
    private func setupCache() {
        // Set cache limits to prevent memory issues
        imageCache.countLimit = 100
        imageCache.totalCostLimit = 50 * 1024 * 1024 // 50MB
        
        thumbnailCache.countLimit = 200
        thumbnailCache.totalCostLimit = 25 * 1024 * 1024 // 25MB
        
        // Clear cache periodically to prevent memory buildup
        // Note: NSMemoryWarning is iOS-only, so we'll use a timer on macOS
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.clearOldCacheEntries()
        }
    }
    
    // MARK: - High-Performance Image Loading
    
    func loadImageAsync(from path: String, size: CGSize? = nil, completion: @escaping (NSImage?) -> Void) {
        totalRequests += 1
        
        // Check cache first
        let cacheKey = generateCacheKey(path: path, size: size)
        if let cachedImage = getCachedImage(for: cacheKey) {
            cacheHits += 1
            updateCacheHitRate()
            DispatchQueue.main.async {
                completion(cachedImage)
            }
            return
        }
        
        // Process image on background queue
        imageProcessingQueue.async { [weak self] in
            guard let self = self else { return }
            
            let startTime = CACurrentMediaTime()
            
            // Load and process image
            let image = self.loadAndProcessImage(from: path, targetSize: size)
            
            let processingTime = CACurrentMediaTime() - startTime
            self.recordProcessingTime(processingTime)
            
            // Cache the result
            if let image = image {
                self.cacheImage(image, for: cacheKey)
            }
            
            // Return on main queue
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }
    
    // MARK: - Thumbnail Generation
    
    func generateThumbnailAsync(from path: String, size: CGSize, completion: @escaping (NSImage?) -> Void) {
        let cacheKey = generateCacheKey(path: path, size: size)
        
        // Check thumbnail cache
        if let cachedThumbnail = getCachedThumbnail(for: cacheKey) {
            cacheHits += 1
            updateCacheHitRate()
            DispatchQueue.main.async {
                completion(cachedThumbnail)
            }
            return
        }
        
        // Generate thumbnail on background queue
        imageProcessingQueue.async { [weak self] in
            guard let self = self else { return }
            
            let startTime = CACurrentMediaTime()
            
            // Generate thumbnail
            let thumbnail = self.generateThumbnail(from: path, size: size)
            
            let processingTime = CACurrentMediaTime() - startTime
            self.recordProcessingTime(processingTime)
            
            // Cache thumbnail
            if let thumbnail = thumbnail {
                self.cacheThumbnail(thumbnail, for: cacheKey)
            }
            
            DispatchQueue.main.async {
                completion(thumbnail)
            }
        }
    }
    
    // MARK: - Profile Image Processing
    
    func processProfileImageAsync(from path: String, size: CGSize, completion: @escaping (NSImage?) -> Void) {
        let cacheKey = generateCacheKey(path: path, size: size, type: "profile")
        
        // Check cache
        if let cachedImage = getCachedImage(for: cacheKey) {
            cacheHits += 1
            updateCacheHitRate()
            DispatchQueue.main.async {
                completion(cachedImage)
            }
            return
        }
        
        // Process profile image on background queue
        imageProcessingQueue.async { [weak self] in
            guard let self = self else { return }
            
            let startTime = CACurrentMediaTime()
            
            // Process profile image (crop to square, resize, etc.)
            let processedImage = self.processProfileImage(from: path, size: size)
            
            let processingTime = CACurrentMediaTime() - startTime
            self.recordProcessingTime(processingTime)
            
            // Cache result
            if let processedImage = processedImage {
                self.cacheImage(processedImage, for: cacheKey)
            }
            
            DispatchQueue.main.async {
                completion(processedImage)
            }
        }
    }
    
    // MARK: - Album Art Processing
    
    func processAlbumArtAsync(from path: String, size: CGSize, completion: @escaping (NSImage?) -> Void) {
        let cacheKey = generateCacheKey(path: path, size: size, type: "album")
        
        // Check cache
        if let cachedImage = getCachedImage(for: cacheKey) {
            cacheHits += 1
            updateCacheHitRate()
            DispatchQueue.main.async {
                completion(cachedImage)
            }
            return
        }
        
        // Process album art on background queue
        imageProcessingQueue.async { [weak self] in
            guard let self = self else { return }
            
            let startTime = CACurrentMediaTime()
            
            // Process album art (maintain aspect ratio, resize, etc.)
            let processedImage = self.processAlbumArt(from: path, size: size)
            
            let processingTime = CACurrentMediaTime() - startTime
            self.recordProcessingTime(processingTime)
            
            // Cache result
            if let processedImage = processedImage {
                self.cacheImage(processedImage, for: cacheKey)
            }
            
            DispatchQueue.main.async {
                completion(processedImage)
            }
        }
    }
    
    // MARK: - Core Image Processing Methods
    
    private func loadAndProcessImage(from path: String, targetSize: CGSize?) -> NSImage? {
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        
        if let targetSize = targetSize {
            return resizeImage(image, to: targetSize)
        }
        
        return image
    }
    
    private func generateThumbnail(from path: String, size: CGSize) -> NSImage? {
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        return resizeImage(image, to: size)
    }
    
    private func processProfileImage(from path: String, size: CGSize) -> NSImage? {
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        
        // Crop to square if needed
        let croppedImage = cropToSquare(image)
        
        // Resize to target size
        return resizeImage(croppedImage, to: size)
    }
    
    private func processAlbumArt(from path: String, size: CGSize) -> NSImage? {
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        
        // Maintain aspect ratio, resize to fit
        return resizeImageMaintainingAspectRatio(image, to: size)
    }
    
    // MARK: - Image Manipulation
    
    private func resizeImage(_ image: NSImage, to size: CGSize) -> NSImage {
        let resizedImage = NSImage(size: size)
        
        resizedImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size))
        resizedImage.unlockFocus()
        
        return resizedImage
    }
    
    private func cropToSquare(_ image: NSImage) -> NSImage {
        let originalSize = image.size
        let minDimension = min(originalSize.width, originalSize.height)
        
        let cropRect = NSRect(
            x: (originalSize.width - minDimension) / 2,
            y: (originalSize.height - minDimension) / 2,
            width: minDimension,
            height: minDimension
        )
        
        let croppedImage = NSImage(size: NSSize(width: minDimension, height: minDimension))
        
        croppedImage.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: NSSize(width: minDimension, height: minDimension)),
            from: cropRect,
            operation: .copy,
            fraction: 1.0
        )
        croppedImage.unlockFocus()
        
        return croppedImage
    }
    
    private func resizeImageMaintainingAspectRatio(_ image: NSImage, to size: CGSize) -> NSImage {
        let originalSize = image.size
        let aspectRatio = originalSize.width / originalSize.height
        let targetAspectRatio = size.width / size.height
        
        var finalSize = size
        
        if aspectRatio > targetAspectRatio {
            // Image is wider, fit to width
            finalSize.height = size.width / aspectRatio
        } else {
            // Image is taller, fit to height
            finalSize.width = size.height * aspectRatio
        }
        
        return resizeImage(image, to: finalSize)
    }
    
    // MARK: - Caching System
    
    private func generateCacheKey(path: String, size: CGSize?, type: String? = nil) -> NSString {
        var key = path
        if let size = size {
            key += "_\(Int(size.width))x\(Int(size.height))"
        }
        if let type = type {
            key += "_\(type)"
        }
        return NSString(string: key)
    }
    
    private func getCachedImage(for key: NSString) -> NSImage? {
        return imageCache.object(forKey: key)
    }
    
    private func getCachedThumbnail(for key: NSString) -> NSImage? {
        return thumbnailCache.object(forKey: key)
    }
    
    private func cacheImage(_ image: NSImage, for key: NSString) {
        imageCacheQueue.async {
            self.imageCache.setObject(image, forKey: key)
        }
    }
    
    private func cacheThumbnail(_ thumbnail: NSImage, for key: NSString) {
        imageCacheQueue.async {
            self.thumbnailCache.setObject(thumbnail, forKey: key)
        }
    }
    
    // MARK: - Performance Monitoring
    
    private func recordProcessingTime(_ time: TimeInterval) {
        processingTimes.append(time)
        
        // Keep only last 100 measurements
        if processingTimes.count > 100 {
            processingTimes.removeFirst()
        }
    }
    
    private func updateCacheHitRate() {
        cacheHitRate = Double(cacheHits) / Double(totalRequests)
    }
    
    func getPerformanceMetrics() -> [String: Any] {
        let avgProcessingTime = processingTimes.isEmpty ? 0 : processingTimes.reduce(0, +) / Double(processingTimes.count)
        let maxProcessingTime = processingTimes.max() ?? 0
        let minProcessingTime = processingTimes.min() ?? 0
        
        return [
            "totalRequests": totalRequests,
            "cacheHits": cacheHits,
            "cacheHitRate": cacheHitRate,
            "averageProcessingTime": avgProcessingTime,
            "maxProcessingTime": maxProcessingTime,
            "minProcessingTime": minProcessingTime,
            "processingQueueSize": processingQueueSize,
            "imageCacheSize": getImageCacheSize(),
            "thumbnailCacheSize": getThumbnailCacheSize()
        ]
    }
    
    // MARK: - Cache Management
    
    func clearCache() {
        imageCacheQueue.async {
            self.imageCache.removeAllObjects()
            self.thumbnailCache.removeAllObjects()
            print("🧹 Image caches cleared")
        }
    }
    
    func clearOldCacheEntries() {
        // Clear caches when they get too large
        let imageCacheSize = getImageCacheSize()
        let thumbnailCacheSize = getThumbnailCacheSize()
        
        if imageCacheSize > 80 || thumbnailCacheSize > 150 {
            print("🧹 Clearing old cache entries due to size")
            clearCache()
        }
    }
    
    // MARK: - Cache Size Helpers
    
    private func getImageCacheSize() -> Int {
        // NSCache doesn't expose count directly, so we'll estimate
        // This is a rough approximation based on the cache limits
        return min(100, Int(Double(imageCache.totalCostLimit) / Double(1024 * 1024)))
    }
    
    private func getThumbnailCacheSize() -> Int {
        // NSCache doesn't expose count directly, so we'll estimate
        // This is a rough approximation based on the cache limits
        return min(200, Int(Double(thumbnailCache.totalCostLimit) / Double(1024 * 1024)))
    }
    
    // MARK: - Batch Processing
    
    func processImagesInBatch(_ paths: [String], size: CGSize, completion: @escaping ([NSImage?]) -> Void) {
        let group = DispatchGroup()
        var results: [NSImage?] = Array(repeating: nil, count: paths.count)
        
        for (index, path) in paths.enumerated() {
            group.enter()
            
            processAlbumArtAsync(from: path, size: size) { image in
                results[index] = image
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            completion(results)
        }
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        clearCache()
        processingTimes.removeAll()
        totalRequests = 0
        cacheHits = 0
        cacheHitRate = 0.0
        
        print("🧹 ImagePerformanceOptimizer cleaned up")
    }
}

// MARK: - SwiftUI View Modifier for Image Performance

struct OptimizedImageModifier: ViewModifier {
    let imagePath: String
    let size: CGSize
    let placeholder: NSImage?
    
    @State private var image: NSImage?
    @State private var isLoading = false
    
    func body(content: Content) -> some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            } else if let placeholder = placeholder {
                Image(nsImage: placeholder)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                content
            }
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        guard image == nil else { return }
        
        isLoading = true
        
        ImagePerformanceOptimizer.shared.processAlbumArtAsync(from: imagePath, size: size) { loadedImage in
            self.image = loadedImage
            self.isLoading = false
        }
    }
}

// MARK: - View Extension

extension View {
    func optimizedImage(path: String, size: CGSize, placeholder: NSImage? = nil) -> some View {
        modifier(OptimizedImageModifier(imagePath: path, size: size, placeholder: placeholder))
    }
}
