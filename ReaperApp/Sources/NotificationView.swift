import SwiftUI

// MARK: - Notification Type

enum NotificationType {
    case success
    case error
    case warning
    case info
    
    var color: Color {
        switch self {
        case .success: return .green
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }
    
    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
}

// MARK: - Notification Model

struct NotificationItem: Identifiable {
    let id = UUID()
    let type: NotificationType
    let title: String
    let message: String?
    let timestamp = Date()
}

// MARK: - Notification Manager

@MainActor
class NotificationManager: ObservableObject {
    @Published var notifications: [NotificationItem] = []
    
    func show(_ type: NotificationType, title: String, message: String? = nil) {
        let notification = NotificationItem(type: type, title: title, message: message)
        
        withAnimation(.spring()) {
            notifications.append(notification)
        }
        
        // Auto-dismiss after 4 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            withAnimation(.spring()) {
                self?.notifications.removeAll { $0.id == notification.id }
            }
        }
    }
    
    func dismiss(_ notification: NotificationItem) {
        withAnimation(.spring()) {
            notifications.removeAll { $0.id == notification.id }
        }
    }
}

// MARK: - Individual Notification View

struct NotificationView: View {
    let notification: NotificationItem
    let onDismiss: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: notification.type.icon)
                .font(.title2)
                .foregroundColor(notification.type.color)
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(notification.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                if let message = notification.message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            // Dismiss button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0.3)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(notification.type.color.opacity(0.3), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Notification Container

struct NotificationContainer: View {
    @ObservedObject var manager: NotificationManager
    
    var body: some View {
        VStack(spacing: 8) {
            ForEach(manager.notifications) { notification in
                NotificationView(
                    notification: notification,
                    onDismiss: {
                        manager.dismiss(notification)
                    }
                )
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    )
                )
            }
        }
        .frame(width: 350)
        .padding()
    }
}

// MARK: - Toast Modifier

struct ToastModifier: ViewModifier {
    @ObservedObject var notificationManager: NotificationManager
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            VStack {
                HStack {
                    Spacer()
                    NotificationContainer(manager: notificationManager)
                }
                Spacer()
            }
            .allowsHitTesting(false)
        }
    }
}

extension View {
    func withNotifications(_ manager: NotificationManager) -> some View {
        modifier(ToastModifier(notificationManager: manager))
    }
}