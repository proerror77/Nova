#!/usr/bin/env python3
"""
更新 Xcode 项目：移除旧文件，添加新文件
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

# 要移除的旧文件
files_to_remove = [
    'Features/GroupChat/Views/StartGroupChatView.swift',
    'Features/Chat/Views/StartGroupChatView.swift'
]

# 要添加的新文件
files_to_add = [
    {
        'path': 'Features/GroupChat/Views/NewChatView.swift',
        'group': 'Features/GroupChat/Views'
    },
    {
        'path': 'Features/Chat/Views/NewChatView.swift',
        'group': 'Features/Chat/Views'
    }
]

try:
    # 打开项目
    project = XcodeProject.load(project_path)

    # 移除旧文件
    for file_path in files_to_remove:
        print(f"移除文件: {file_path}")
        try:
            project.remove_file(file_path)
        except:
            print(f"  警告: 文件可能已经被移除")

    # 添加新文件
    for file_info in files_to_add:
        file_path = file_info['path']
        group_path = file_info['group']

        print(f"添加文件: {file_path}")
        project.add_file(file_path, parent=project.get_or_create_group(group_path))

    # 保存项目
    project.save()
    print("\n✅ 成功更新项目文件！")
    print("请在 Xcode 中重新构建项目。")

except Exception as e:
    print(f"\n❌ 错误: {e}")
    print("\n建议在 Xcode 中手动操作：")
    print("1. 删除旧的 StartGroupChatView.swift 文件")
    print("2. 添加新的 NewChatView.swift 文件")
    sys.exit(1)
