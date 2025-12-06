#!/usr/bin/env python3
"""
添加 NewChatView.swift 到 Xcode 项目
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
        'path': 'Features/Chat/Views/NewChatView.swift',
        'group': 'Features/Chat/Views'
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

        # 添加文件到项目和所有目标
        file_ref = project.add_file(file_path, parent=project.get_or_create_group(group_path))

        # 将文件添加到编译目标
        if file_ref:
            # 查找主应用目标
            for target in project.objects.get_targets():
                if target.name == 'ICERED':
                    project.add_file_to_target(file_ref, target)
                    print(f"  已添加到目标: {target.name}")

    # 保存项目
    project.save()
    print("\n✅ 成功添加文件到项目！")

except Exception as e:
    print(f"\n❌ 错误: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
