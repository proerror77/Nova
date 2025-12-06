#!/usr/bin/env python3
"""
自动将新文件添加到 Xcode 项目
需要安装: pip install pbxproj
"""

import sys
try:
    from pbxproj import XcodeProject
except ImportError:
    print("错误: 需要安装 pbxproj 库")
    print("请运行: pip3 install pbxproj")
    sys.exit(1)

# 项目路径
project_path = '/Users/bruce/Documents/Nova/ios/NovaSocial/ICERED.xcodeproj/project.pbxproj'

# 要添加的文件
files_to_add = [
    {
        'path': 'Shared/Models/User/DeviceModels.swift',
        'group': 'Shared/Models/User'
    },
    {
        'path': 'Shared/Services/User/DeviceService.swift',
        'group': 'Shared/Services/User'
    },
    {
        'path': 'Shared/Services/Friends/FriendsService.swift',
        'group': 'Shared/Services/Friends'
    }
]

try:
    # 打开项目
    project = XcodeProject.load(project_path)

    # 添加文件
    for file_info in files_to_add:
        file_path = file_info['path']
        group_path = file_info['group']

        print(f"添加文件: {file_path}")

        # 添加文件到项目
        project.add_file(file_path, parent=project.get_or_create_group(group_path))

    # 保存项目
    project.save()
    print("\n✅ 成功添加所有文件到项目！")
    print("请在 Xcode 中重新构建项目。")

except Exception as e:
    print(f"\n❌ 错误: {e}")
    print("\n建议使用方案一：在 Xcode 中手动添加文件。")
    sys.exit(1)
