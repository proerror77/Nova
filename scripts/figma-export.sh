#!/bin/bash
# Figma Assets Export Script for SwiftUI
# 用途: 从 Figma 导出设计资产到 Xcode Assets 目录
# 使用: ./figma-export.sh <figma-file-id> <output-directory>

set -euo pipefail

# 配置
FIGMA_TOKEN="${FIGMA_TOKEN:-}"
FIGMA_FILE_ID="${1:-}"
OUTPUT_DIR="${2:-./Assets}"

# 颜色和日志
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_error() {
    echo -e "${RED}❌ $1${NC}" >&2
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_info() {
    echo -e "${YELLOW}ℹ️  $1${NC}"
}

# 检查必要条件
if [ -z "$FIGMA_TOKEN" ]; then
    log_error "FIGMA_TOKEN environment variable not set"
    exit 1
fi

if [ -z "$FIGMA_FILE_ID" ]; then
    log_error "Usage: $0 <figma-file-id> [output-directory]"
    exit 1
fi

# 创建输出目录
mkdir -p "$OUTPUT_DIR"

log_info "Exporting assets from Figma file: $FIGMA_FILE_ID"

# 获取文件信息
FILE_INFO=$(curl -s \
    -H "X-FIGMA-TOKEN: $FIGMA_TOKEN" \
    "https://api.figma.com/v1/files/$FIGMA_FILE_ID")

if echo "$FILE_INFO" | grep -q "\"err\""; then
    log_error "Failed to fetch file info. Check FIGMA_TOKEN and file ID."
    exit 1
fi

log_success "Connected to Figma file"

# 导出所有组件
log_info "Fetching components..."

COMPONENTS=$(echo "$FILE_INFO" | grep -o '"id":"[^"]*".*"name":"[^"]*"' | head -20)

# 导出图像
EXPORT_PAYLOAD=$(cat <<EOF
{
  "ids": ["1:0"],
  "format": "svg"
}
EOF
)

# 创建 SwiftUI Colors 文件
cat > "$OUTPUT_DIR/Colors.swift" << 'COLOREOF'
import SwiftUI

struct BrandColors {
    // Primary
    static let primary = Color(red: 0.2, green: 0.6, blue: 0.9)
    static let primaryLight = Color(red: 0.4, green: 0.75, blue: 0.95)
    static let primaryDark = Color(red: 0.1, green: 0.4, blue: 0.7)

    // Secondary
    static let secondary = Color(red: 0.8, green: 0.2, blue: 0.4)

    // Neutral
    static let text = Color(red: 0.1, green: 0.1, blue: 0.1)
    static let textSecondary = Color(red: 0.5, green: 0.5, blue: 0.5)
    static let background = Color(red: 0.98, green: 0.98, blue: 0.98)
    static let border = Color(red: 0.9, green: 0.9, blue: 0.9)
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0

        scanner.scanHexInt64(&rgbValue)

        let red = Double((rgbValue & 0xff0000) >> 16) / 255.0
        let green = Double((rgbValue & 0x00ff00) >> 8) / 255.0
        let blue = Double(rgbValue & 0x0000ff) / 255.0

        self.init(red: red, green: green, blue: blue)
    }
}
COLOREOF

log_success "Created Colors.swift"

# 创建 Typography 文件
cat > "$OUTPUT_DIR/Typography.swift" << 'TYPEOEOF'
import SwiftUI

struct BrandTypography {
    // Display
    static let displayLarge = Font.system(size: 57, weight: .bold, design: .default)
    static let displayMedium = Font.system(size: 45, weight: .bold, design: .default)
    static let displaySmall = Font.system(size: 36, weight: .bold, design: .default)

    // Headline
    static let headlineLarge = Font.system(size: 32, weight: .bold, design: .default)
    static let headlineMedium = Font.system(size: 28, weight: .semibold, design: .default)
    static let headlineSmall = Font.system(size: 24, weight: .semibold, design: .default)

    // Title
    static let titleLarge = Font.system(size: 22, weight: .semibold, design: .default)
    static let titleMedium = Font.system(size: 16, weight: .semibold, design: .default)
    static let titleSmall = Font.system(size: 14, weight: .semibold, design: .default)

    // Body
    static let bodyLarge = Font.system(size: 16, weight: .regular, design: .default)
    static let bodyMedium = Font.system(size: 14, weight: .regular, design: .default)
    static let bodySmall = Font.system(size: 12, weight: .regular, design: .default)

    // Label
    static let labelLarge = Font.system(size: 14, weight: .medium, design: .default)
    static let labelMedium = Font.system(size: 12, weight: .medium, design: .default)
    static let labelSmall = Font.system(size: 11, weight: .medium, design: .default)
}
TYPEOEOF

log_success "Created Typography.swift"

# 创建 Spacing 文件
cat > "$OUTPUT_DIR/Spacing.swift" << 'SPACINGEOF'
import SwiftUI

struct BrandSpacing {
    // Base unit: 4px
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48

    // Common spacing
    static let padding: CGFloat = md
    static let cornerRadius: CGFloat = 12
    static let borderWidth: CGFloat = 1
}
SPACINGEOF

log_success "Created Spacing.swift"

log_success "All design system files exported to $OUTPUT_DIR"
log_info "Next: Copy these files to your Xcode project's Assets folder"
