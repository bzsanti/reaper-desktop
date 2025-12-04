import SwiftUI

struct ResizableTableHeader: View {
    let title: String
    let columnId: String
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    @State private var isDragging = false
    @State private var startWidth: CGFloat = 0
    @State private var startLocation: CGFloat = 0
    
    var body: some View {
        HStack(spacing: 0) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
            
            // Resize handle
            Rectangle()
                .fill(Color.clear)
                .frame(width: 8, height: 20)
                .contentShape(Rectangle())
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .background(
                    isDragging ? Color.accentColor.opacity(0.3) : Color.clear
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if !isDragging {
                                isDragging = true
                                startWidth = width
                                startLocation = value.startLocation.x
                            }
                            
                            let delta = value.location.x - startLocation
                            let newWidth = startWidth + delta
                            width = min(maxWidth, max(minWidth, newWidth))
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
        }
        .frame(width: width)
    }
}

// Custom Table implementation with resizable columns
struct ResizableTable<Data: RandomAccessCollection>: View where Data.Element: Identifiable {
    let data: Data
    let columns: [TableColumnDefinition]
    @Binding var selection: Set<Data.Element.ID>
    @Binding var sortOrder: [KeyPathComparator<Data.Element>]
    @EnvironmentObject var appState: AppState
    
    struct TableColumnDefinition {
        let id: String
        let title: String
        let minWidth: CGFloat
        let maxWidth: CGFloat
        let content: (Data.Element) -> AnyView
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 0) {
                ForEach(columns, id: \.id) { column in
                    ResizableTableHeader(
                        title: column.title,
                        columnId: column.id,
                        width: .init(
                            get: { appState.columnWidths[column.id] ?? 100 },
                            set: { appState.updateColumnWidth(for: column.id, width: $0) }
                        ),
                        minWidth: column.minWidth,
                        maxWidth: column.maxWidth
                    )
                    .background(Color.gray.opacity(0.1))
                    .overlay(
                        Rectangle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                    )
                }
            }
            .frame(height: 30)
            
            Divider()
            
            // Content
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(data) { item in
                        HStack(spacing: 0) {
                            ForEach(columns, id: \.id) { column in
                                column.content(item)
                                    .frame(width: appState.columnWidths[column.id] ?? 100)
                                    .padding(.horizontal, 8)
                                    .frame(height: 28)
                                    .overlay(
                                        Rectangle()
                                            .stroke(Color.gray.opacity(0.1), lineWidth: 0.5)
                                    )
                            }
                        }
                        .background(
                            selection.contains(item.id) ? 
                            Color.accentColor.opacity(0.2) : 
                            Color.clear
                        )
                        .onTapGesture {
                            if NSEvent.modifierFlags.contains(.shift) {
                                // Shift-click for range selection
                                selection.insert(item.id)
                            } else if NSEvent.modifierFlags.contains(.command) {
                                // Cmd-click for toggle
                                if selection.contains(item.id) {
                                    selection.remove(item.id)
                                } else {
                                    selection.insert(item.id)
                                }
                            } else {
                                // Normal click
                                selection = [item.id]
                            }
                        }
                    }
                }
            }
        }
    }
}