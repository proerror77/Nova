import SwiftUI

struct LocationView: View {
    @Binding var showLocation: Bool

    var body: some View {
        ZStack {
            // MARK: - 背景色
            Color(red: 0.97, green: 0.96, blue: 0.96)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // MARK: - 顶部栏（导航）
                HStack(spacing: 16) {
                    // 返回按钮
                    Button(action: { showLocation = false }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.black)
                    }

                    Spacer()

                    Text("Location")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.black)

                    Spacer()

                    // 发送按钮（箭头）
                    Button(action: {}) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color(red: 0.82, green: 0.13, blue: 0.25))
                    }
                }
                .frame(height: DesignTokens.topBarHeight)
                .padding(.horizontal, 16)
                .background(.white)

                // MARK: - 顶部分割线
                Divider()
                    .frame(height: 0.5)
                    .background(Color(red: 0.74, green: 0.74, blue: 0.74))

                // MARK: - 搜索框
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15))
                        .foregroundColor(Color(red: 0.69, green: 0.68, blue: 0.68))

                    Text("Search")
                        .font(.system(size: 15))
                        .foregroundColor(Color(red: 0.69, green: 0.68, blue: 0.68))

                    Spacer()
                }
                .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .frame(height: 32)
                .background(Color(red: 0.89, green: 0.88, blue: 0.87))
                .cornerRadius(37)
                .padding(EdgeInsets(top: 12, leading: 18, bottom: 16, trailing: 18))

                // MARK: - 位置列表
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(0..<9, id: \.self) { index in
                            LocationListItem()

                            if index < 8 {
                                Divider()
                                    .frame(height: 0.5)
                                    .background(Color(red: 0.80, green: 0.80, blue: 0.80))
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                }

                Spacer()

                // MARK: - 底部按钮
                Button(action: {}) {
                    Text("Add-location")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(Color(red: 0.82, green: 0.13, blue: 0.25))
                        .cornerRadius(38)
                }
                .padding(EdgeInsets(top: 0, leading: 18, bottom: 20, trailing: 18))
            }
        }
    }
}

struct LocationListItem: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Shanghai, China")
                .font(.system(size: 20))
                .foregroundColor(.black)

            Text("6.2km")
                .font(.system(size: 16))
                .foregroundColor(Color(red: 0.55, green: 0.55, blue: 0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }
}

#Preview {
    @Previewable @State var showLocation = true
    LocationView(showLocation: $showLocation)
}
