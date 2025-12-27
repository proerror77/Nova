import SwiftUI

/// ICERED 品牌展示 Banner - Feed 顶部
struct PromoBannerView: View {
    var onTap: (() -> Void)?

    var body: some View {
        Button(action: { onTap?() }) {
            ZStack {
                // 背景 - 云雾效果
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color(red: 0.95, green: 0.97, blue: 0.98),
                                Color(red: 0.90, green: 0.94, blue: 0.96),
                                Color(red: 0.85, green: 0.91, blue: 0.95)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                // 云朵装饰效果
                GeometryReader { geometry in
                    // 左侧云朵
                    Ellipse()
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 120, height: 60)
                        .blur(radius: 20)
                        .offset(x: -20, y: geometry.size.height * 0.3)

                    // 右侧云朵
                    Ellipse()
                        .fill(Color.white.opacity(0.7))
                        .frame(width: 150, height: 70)
                        .blur(radius: 25)
                        .offset(x: geometry.size.width - 100, y: geometry.size.height * 0.4)

                    // 中间云朵
                    Ellipse()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: 200, height: 80)
                        .blur(radius: 30)
                        .offset(x: geometry.size.width * 0.3, y: geometry.size.height * 0.2)
                }

                // 内容
                VStack(spacing: 8) {
                    // ICERED Logo
                    Image("home-icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 40)

                    // 标语文字
                    Text("This is ICERED.")
                        .font(.system(size: 24))
                        .tracking(0.24)
                        .foregroundColor(Color(red: 0.87, green: 0.11, blue: 0.26))
                }
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }
}

#Preview {
    VStack {
        PromoBannerView()
    }
    .padding()
    .background(DesignTokens.backgroundColor)
}
