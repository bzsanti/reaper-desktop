import SwiftUI
import UniformTypeIdentifiers

// MARK: - Column Drag & Drop Support

struct ColumnDropDelegate: DropDelegate {
    let columnId: String
    @Binding var columnOrder: [String]
    @Binding var draggedColumn: String?
    
    func performDrop(info: DropInfo) -> Bool {
        guard let draggedColumn = draggedColumn else { return false }
        
        let fromIndex = columnOrder.firstIndex(of: draggedColumn) ?? 0
        let toIndex = columnOrder.firstIndex(of: columnId) ?? 0
        
        if fromIndex != toIndex {
            withAnimation {
                columnOrder.move(
                    fromOffsets: IndexSet(integer: fromIndex),
                    toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
                )
            }
        }
        
        self.draggedColumn = nil
        return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let draggedColumn = draggedColumn,
              draggedColumn != columnId else { return }
        
        let from = columnOrder.firstIndex(of: draggedColumn) ?? 0
        let to = columnOrder.firstIndex(of: columnId) ?? 0
        
        if from != to {
            withAnimation(.default) {
                columnOrder.move(
                    fromOffsets: IndexSet(integer: from),
                    toOffset: to > from ? to + 1 : to
                )
            }
        }
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        return info.hasItemsConforming(to: [.text])
    }
}

// MARK: - Enhanced Table Header

struct EnhancedTableHeader<T: Comparable>: View {
    let title: String
    let columnId: String
    let sortKeyPath: KeyPath<ProcessInfo, T>?
    @Binding var sortOrder: [KeyPathComparator<ProcessInfo>]
    @Binding var width: CGFloat
    @Binding var draggedColumn: String?
    @Binding var columnOrder: [String]
    let minWidth: CGFloat
    let maxWidth: CGFloat
    
    @State private var isDraggingResize = false
    @State private var startWidth: CGFloat = 0
    @State private var isHoveringResize = false
    
    var isSorted: Bool {
        if sortKeyPath != nil,
           !sortOrder.isEmpty {
            // This is a simplified check - would need proper implementation
            return true // Placeholder
        }
        return false
    }
    
    var sortDirection: SortOrder? {
        if isSorted, let first = sortOrder.first {
            return first.order
        }
        return nil
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Column content
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                
                Spacer()
                
                // Sort indicator
                if let direction = sortDirection {
                    Image(systemName: direction == .forward ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(width: width - 4)
            .contentShape(Rectangle())
            .onTapGesture {
                // Toggle sort when clicking header
                if let keyPath = sortKeyPath {
                    toggleSort(for: keyPath)
                }
            }
            .draggable(columnId) {
                Text(title)
                    .padding(4)
                    .background(Color.accentColor.opacity(0.2))
                    .cornerRadius(4)
                    .onAppear {
                        draggedColumn = columnId
                    }
            }
            .onDrop(of: [.text], delegate: ColumnDropDelegate(
                columnId: columnId,
                columnOrder: $columnOrder,
                draggedColumn: $draggedColumn
            ))
            
            // Resize handle
            Rectangle()
                .fill(isHoveringResize ? Color.accentColor.opacity(0.5) : Color.clear)
                .frame(width: 4)
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHoveringResize = hovering
                    if hovering {
                        NSCursor.resizeLeftRight.push()
                    } else if !isDraggingResize {
                        NSCursor.pop()
                    }
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if !isDraggingResize {
                                isDraggingResize = true
                                startWidth = width
                            }
                            
                            let newWidth = startWidth + value.translation.width
                            width = min(maxWidth, max(minWidth, newWidth))
                        }
                        .onEnded { _ in
                            isDraggingResize = false
                            if !isHoveringResize {
                                NSCursor.pop()
                            }
                        }
                )
        }
        .frame(height: 28)
        .background(Color.gray.opacity(0.05))
        .overlay(
            Rectangle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
        )
    }
    
    private func toggleSort(for keyPath: KeyPath<ProcessInfo, T>) {
        // This would need proper implementation based on the keyPath
        // For now, it's a placeholder
        withAnimation {
            if let first = sortOrder.first {
                if first.order == .reverse {
                    sortOrder[0] = KeyPathComparator(keyPath, order: .forward)
                } else {
                    sortOrder[0] = KeyPathComparator(keyPath, order: .reverse)
                }
            } else {
                sortOrder = [KeyPathComparator(keyPath, order: .reverse)]
            }
        }
    }
}

// MARK: - Table Configuration Menu

struct TableConfigurationMenu: View {
    @EnvironmentObject var appState: AppState
    @State private var showingColumnPicker = false
    
    let availableColumns = [
        ("pid", "PID"),
        ("name", "Name"),
        ("cpu", "CPU %"),
        ("memory", "Memory"),
        ("status", "Status"),
        ("threads", "Threads"),
        ("runtime", "Runtime"),
        ("parent_pid", "Parent PID"),
        ("user_time", "User Time"),
        ("system_time", "System Time")
    ]
    
    var body: some View {
        Menu {
            // Column visibility
            Menu("Columns") {
                ForEach(availableColumns, id: \.0) { columnId, columnName in
                    Button(action: {
                        toggleColumn(columnId)
                    }) {
                        HStack {
                            if appState.columnOrder.contains(columnId) {
                                Image(systemName: "checkmark")
                            }
                            Text(columnName)
                        }
                    }
                }
                
                Divider()
                
                Button("Reset to Default") {
                    appState.resetColumnOrder()
                    appState.resetColumnWidths()
                }
            }
            
            Divider()
            
            // Quick actions
            Button("Reset Column Widths") {
                appState.resetColumnWidths()
            }
            
            Button("Reset Column Order") {
                appState.resetColumnOrder()
            }
            
        } label: {
            Image(systemName: "gearshape")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 20, height: 20)
    }
    
    private func toggleColumn(_ columnId: String) {
        if appState.columnOrder.contains(columnId) {
            appState.hideColumn(columnId)
        } else {
            appState.showColumn(columnId)
        }
    }
}

// MARK: - Selection Info Bar

struct SelectionInfoBar: View {
    let selectedCount: Int
    let totalCount: Int
    let onClearSelection: () -> Void
    
    var body: some View {
        if selectedCount > 0 {
            HStack {
                Text("\(selectedCount) of \(totalCount) selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Clear") {
                    onClearSelection()
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.gray.opacity(0.1))
        }
    }
}