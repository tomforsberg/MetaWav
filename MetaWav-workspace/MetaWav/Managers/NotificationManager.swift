import Foundation

/// Simple notification manager to prevent spam
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    private var lastNotificationTime: [String: Date] = [:]
    private let throttleTime: TimeInterval = 0.1 // 100ms
    
    private init() {}
    
    /// Post notification with throttling to prevent spam
    func postNotification(_ name: Notification.Name, object: Any? = nil, userInfo: [AnyHashable: Any]? = nil) {
        let key = name.rawValue
        let now = Date()
        
        if let lastTime = lastNotificationTime[key],
           now.timeIntervalSince(lastTime) < throttleTime {
            return // Skip if too soon
        }
        
        lastNotificationTime[key] = now
        NotificationCenter.default.post(name: name, object: object, userInfo: userInfo)
    }
    
    /// Simple log function
    func log(_ message: String) {
        print("[MetaWav] \(message)")
    }
}
