import Foundation

/// Handles channel management for feed filtering
/// Extracted from FeedViewModel to follow Single Responsibility Principle
@MainActor
@Observable
final class FeedChannelManager {
    // MARK: - Observable State
    
    /// Available channels
    var channels: [FeedChannel] = []
    
    /// Currently selected channel ID (nil = "For You" / all content)
    var selectedChannelId: String? = nil
    
    /// Loading state for channels
    var isLoadingChannels = false
    
    // MARK: - Dependencies
    
    private let feedService: FeedService
    private let performanceMonitor: FeedPerformanceMonitor
    
    // MARK: - Callbacks
    
    /// Callback to reload feed when channel changes
    var onChannelSelected: ((String?) async -> Void)?
    
    // MARK: - Init
    
    init(
        feedService: FeedService = FeedService(),
        performanceMonitor: FeedPerformanceMonitor = .shared
    ) {
        self.feedService = feedService
        self.performanceMonitor = performanceMonitor
    }
    
    // MARK: - Channel Loading
    
    /// Load available channels from backend
    func loadChannels() async {
        guard !isLoadingChannels else { return }
        isLoadingChannels = true
        
        do {
            channels = try await feedService.getChannels(enabledOnly: true)
            #if DEBUG
            print("[FeedChannelManager] Loaded \(channels.count) channels")
            #endif
        } catch {
            #if DEBUG
            print("[FeedChannelManager] Failed to load channels: \(error)")
            #endif
            // Use fallback channels when API is unavailable
            channels = FeedChannel.fallbackChannels
        }
        
        isLoadingChannels = false
    }
    
    // MARK: - Channel Selection
    
    /// Select a channel and reload feed
    /// - Parameter channelId: Channel ID to filter by, or nil for "For You" (all content)
    func selectChannel(_ channelId: String?) async {
        guard selectedChannelId != channelId else { return }
        
        selectedChannelId = channelId
        
        // Track channel selection for analytics
        if let channelId = channelId,
           let channel = channels.first(where: { $0.id == channelId }) {
            #if DEBUG
            print("[FeedChannelManager] Selected channel: \(channel.name) (\(channelId))")
            #endif
            // TODO: Add analytics tracking
            // AnalyticsService.shared.track(.channelTabClick, properties: ["channel_id": channelId, "channel_name": channel.name])
        } else {
            #if DEBUG
            print("[FeedChannelManager] Selected: For You (all content)")
            #endif
        }
        
        // Track channel switch timing
        let loadStartTime = Date()
        _ = performanceMonitor.beginFeedLoad(source: .channelSwitch, fromCache: false)
        
        // Notify to reload feed with new channel filter
        await onChannelSelected?(channelId)
        
        let duration = Date().timeIntervalSince(loadStartTime)
        #if DEBUG
        print("[FeedChannelManager] Channel switch completed in \(String(format: "%.2f", duration))s")
        #endif
    }
    
    // MARK: - Helpers
    
    /// Get channel by ID
    func channel(for id: String?) -> FeedChannel? {
        guard let id = id else { return nil }
        return channels.first { $0.id == id }
    }
    
    /// Get selected channel
    var selectedChannel: FeedChannel? {
        channel(for: selectedChannelId)
    }
    
    /// Check if "For You" (all content) is selected
    var isForYouSelected: Bool {
        selectedChannelId == nil
    }
}
