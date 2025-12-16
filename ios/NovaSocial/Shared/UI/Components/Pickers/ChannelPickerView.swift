import SwiftUI

/// Multi-select channel picker for post creation
/// Allows users to select up to 3 channels for their post
struct ChannelPickerView: View {
    @Binding var selectedChannelIds: [String]
    @Binding var isPresented: Bool

    @State private var channels: [FeedChannel] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var error: String?

    private let feedService = FeedService()
    private let maxChannels = 3

    private var filteredChannels: [FeedChannel] {
        if searchText.isEmpty {
            return channels
        }
        return channels.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.description?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Selection count indicator
                if !selectedChannelIds.isEmpty {
                    HStack {
                        Text("\(selectedChannelIds.count)/\(maxChannels) selected")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color(red: 0.82, green: 0.13, blue: 0.25))
                        Spacer()
                        Button("Clear All") {
                            selectedChannelIds.removeAll()
                        }
                        .font(.system(size: 13))
                        .foregroundColor(.red)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.98, green: 0.95, blue: 0.96))
                }

                // Search bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundColor(Color(red: 0.69, green: 0.68, blue: 0.68))

                    TextField("Search channels", text: $searchText)
                        .font(.system(size: 15))
                        .foregroundColor(.black)
                        .autocorrectionDisabled()

                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundColor(Color(red: 0.69, green: 0.68, blue: 0.68))
                        }
                    }
                }
                .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .background(Color(red: 0.93, green: 0.93, blue: 0.93))
                .cornerRadius(10)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                // Content
                if isLoading {
                    Spacer()
                    ProgressView("Loading channels...")
                    Spacer()
                } else if let error = error {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task { await loadChannels() }
                        }
                        .foregroundColor(Color(red: 0.82, green: 0.13, blue: 0.25))
                    }
                    .padding()
                    Spacer()
                } else {
                    // Channel list
                    List {
                        ForEach(filteredChannels) { channel in
                            ChannelRow(
                                channel: channel,
                                isSelected: selectedChannelIds.contains(channel.id),
                                isDisabled: !selectedChannelIds.contains(channel.id) && selectedChannelIds.count >= maxChannels,
                                onTap: {
                                    toggleChannel(channel)
                                }
                            )
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(Color(red: 0.97, green: 0.97, blue: 0.97))
            .navigationTitle("Select Channels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(Color(red: 0.82, green: 0.13, blue: 0.25))
                }
            }
        }
        .task {
            await loadChannels()
        }
    }

    private func loadChannels() async {
        isLoading = true
        error = nil

        do {
            channels = try await feedService.getChannels()
            isLoading = false
        } catch {
            self.error = "Failed to load channels"
            // Use fallback channels
            channels = FeedChannel.fallbackChannels
            isLoading = false
            #if DEBUG
            print("[ChannelPicker] Error loading channels: \(error)")
            #endif
        }
    }

    private func toggleChannel(_ channel: FeedChannel) {
        if let index = selectedChannelIds.firstIndex(of: channel.id) {
            // Deselect
            selectedChannelIds.remove(at: index)
        } else if selectedChannelIds.count < maxChannels {
            // Select
            selectedChannelIds.append(channel.id)
        }
    }
}

// MARK: - Channel Row

private struct ChannelRow: View {
    let channel: FeedChannel
    let isSelected: Bool
    let isDisabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Channel icon or placeholder
                ZStack {
                    Circle()
                        .fill(Color(red: 0.91, green: 0.91, blue: 0.91))
                        .frame(width: 40, height: 40)

                    Text("#")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                }

                // Channel info
                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isDisabled ? .gray : .black)

                    if let description = channel.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 12))
                            .foregroundColor(Color(red: 0.53, green: 0.53, blue: 0.53))
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Color(red: 0.82, green: 0.13, blue: 0.25))
                } else if !isDisabled {
                    Circle()
                        .strokeBorder(Color(red: 0.77, green: 0.77, blue: 0.77), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
    }
}

#Preview {
    @Previewable @State var selectedChannelIds: [String] = []
    @Previewable @State var isPresented = true

    ChannelPickerView(
        selectedChannelIds: $selectedChannelIds,
        isPresented: $isPresented
    )
}
