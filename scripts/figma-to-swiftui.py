#!/usr/bin/env python3
"""
Figma to SwiftUI Component Generator
将 Figma 设计转换为 SwiftUI 代码
"""

import os
import json
import requests
import sys
from typing import Dict, List, Any
from datetime import datetime

class FigmaToSwiftUI:
    """Figma 设计转 SwiftUI 的转换器"""

    def __init__(self, token: str, file_id: str):
        self.token = token
        self.file_id = file_id
        self.base_url = "https://api.figma.com/v1"
        self.headers = {"X-FIGMA-TOKEN": token}

    def fetch_file(self) -> Dict[str, Any]:
        """获取 Figma 文件信息"""
        url = f"{self.base_url}/files/{self.file_id}"
        response = requests.get(url, headers=self.headers)
        response.raise_for_status()
        return response.json()

    def fetch_components(self) -> Dict[str, Any]:
        """获取所有组件"""
        url = f"{self.base_url}/files/{self.file_id}/components"
        response = requests.get(url, headers=self.headers)
        response.raise_for_status()
        return response.json()

    def generate_button_component(self, name: str, props: Dict) -> str:
        """生成按钮组件代码"""
        button_size = props.get("size", "medium")
        button_variant = props.get("variant", "primary")

        size_map = {
            "small": ("14", "8", "12"),
            "medium": ("16", "12", "16"),
            "large": ("18", "16", "20"),
        }

        font_size, padding_v, padding_h = size_map.get(button_size, size_map["medium"])

        return f'''import SwiftUI

struct {name}: View {{
    @State private var isPressed = false
    var action: () -> Void = {{}}
    var label: String = "Button"

    var body: some View {{
        Button(action: action) {{
            Text(label)
                .font(.system(size: {font_size}, weight: .semibold, design: .default))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, {padding_v})
                .padding(.horizontal, {padding_h})
                .background(backgroundColor)
                .cornerRadius(BrandSpacing.cornerRadius)
                .scaleEffect(isPressed ? 0.95 : 1.0)
        }}
        .onLongPressGesture(
            minimumDuration: 0,
            pressing: {{ pressing in
                withAnimation(.easeInOut(duration: 0.1)) {{
                    isPressed = pressing
                }}
            }},
            perform: {{}}
        )
    }}

    private var backgroundColor: Color {{
        switch "{button_variant}" {{
        case "secondary":
            return BrandColors.secondary
        case "disabled":
            return BrandColors.border
        default:
            return BrandColors.primary
        }}
    }}
}}

#Preview {{
    {name}(label: "Click me")
}}
'''

    def generate_card_component(self, name: str, props: Dict) -> str:
        """生成卡片组件代码"""
        return f'''import SwiftUI

struct {name}<Content: View>: View {{
    let content: () -> Content
    var backgroundColor: Color = BrandColors.background
    var borderColor: Color = BrandColors.border
    var cornerRadius: CGFloat = BrandSpacing.cornerRadius
    var shadow: Bool = true

    var body: some View {{
        VStack {{
            content()
        }}
        .padding(BrandSpacing.md)
        .background(backgroundColor)
        .border(borderColor, width: BrandSpacing.borderWidth)
        .cornerRadius(cornerRadius)
        .shadow(color: Color.black.opacity(shadow ? 0.1 : 0), radius: 8)
    }}
}}

#Preview {{
    {name} {{
        Text("Card Content")
            .font(BrandTypography.bodyLarge)
    }}
}}
'''

    def generate_input_field_component(self, name: str, props: Dict) -> str:
        """生成输入框组件代码"""
        return f'''import SwiftUI

struct {name}: View {{
    @Binding var text: String
    var placeholder: String = "Enter text..."
    var isSecure: Bool = false
    var isDisabled: Bool = false

    var body: some View {{
        if isSecure {{
            SecureField(placeholder, text: $text)
                .textFieldStyle()
                .disabled(isDisabled)
        }} else {{
            TextField(placeholder, text: $text)
                .textFieldStyle()
                .disabled(isDisabled)
        }}
    }}
}}

struct TextFieldStyle: ViewModifier {{
    func body(content: Content) -> some View {{
        content
            .padding(BrandSpacing.sm)
            .background(BrandColors.background)
            .border(BrandColors.border, width: BrandSpacing.borderWidth)
            .cornerRadius(BrandSpacing.cornerRadius)
            .font(BrandTypography.bodyMedium)
    }}
}}

#Preview {{
    @State var text = ""
    return {name}(text: $text, placeholder: "Email")
}}
'''

    def generate_components(self, output_dir: str = "./Sources/Components"):
        """生成所有组件"""
        os.makedirs(output_dir, exist_ok=True)

        components = {
            "PrimaryButton": self.generate_button_component("PrimaryButton", {"size": "medium", "variant": "primary"}),
            "SecondaryButton": self.generate_button_component("SecondaryButton", {"size": "medium", "variant": "secondary"}),
            "Card": self.generate_card_component("Card", {}),
            "InputField": self.generate_input_field_component("InputField", {"isSecure": False}),
        }

        for comp_name, comp_code in components.items():
            filename = f"{output_dir}/{comp_name}.swift"
            with open(filename, "w") as f:
                f.write(comp_code)
            print(f"✅ Generated {comp_name}.swift")

        # 生成 ComponentLibrary 索引文件
        self.generate_library_index(output_dir, components.keys())

    def generate_library_index(self, output_dir: str, component_names):
        """生成组件库索引文件"""
        index_content = f'''import SwiftUI

/**
 # Nova Design System - Component Library

 Generated on: {datetime.now().isoformat()}

 Available Components:
'''
        for name in component_names:
            index_content += f" - `{name}`\n"

        index_content += f'''
 ## Usage

 Import any component and use it in your SwiftUI views:

 ```swift
 import SwiftUI

 struct ContentView: View {{
     var body: some View {{
         PrimaryButton(label: "Get Started", action: {{ }})
     }}
 }}
 ```
 */

public struct ComponentLibrary {{
    public static let version = "1.0.0"
    public static let lastUpdated = "{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
}}
'''

        with open(f"{output_dir}/ComponentLibrary.swift", "w") as f:
            f.write(index_content)
        print("✅ Generated ComponentLibrary.swift")


def main():
    token = os.getenv("FIGMA_TOKEN")
    if not token:
        print("❌ FIGMA_TOKEN environment variable not set")
        sys.exit(1)

    # 使用你的 Figma 文件 ID
    file_id = "DoBJCFQ7WzELIXnwQcbVls"

    try:
        converter = FigmaToSwiftUI(token, file_id)
        print(f"🔗 Connecting to Figma file: {file_id}")

        # 测试连接
        file_data = converter.fetch_file()
        print(f"✅ Connected to: {file_data['name']}")

        # 生成组件
        converter.generate_components(output_dir="./ios/NovaSocial/DesignSystem/Components")
        print("\n✅ All components generated successfully!")

    except requests.exceptions.RequestException as e:
        print(f"❌ API Error: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
