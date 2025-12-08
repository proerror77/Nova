#!/usr/bin/env python3
"""
Script to add StartGroupChatView.swift to Xcode project.pbxproj

Target: Features/GroupChat/Views/StartGroupChatView.swift
Group ID: 2F4594B2B14AE664BBCA5220 (GroupChat/Views)
"""

import re

def read_file(path):
    with open(path, 'r') as f:
        return f.read()

def write_file(path, content):
    with open(path, 'w') as f:
        f.write(content)

def add_to_pbxproj(content):
    file_ref_id = "STARTGROUPCHAT_REF"
    build_file_id = "STARTGROUPCHAT_BLD"
    file_name = "StartGroupChatView.swift"
    group_id = "2F4594B2B14AE664BBCA5220"  # GroupChat/Views group

    # 1. Add PBXBuildFile entry
    build_file_entry = f'\t\t{build_file_id} /* {file_name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_ref_id} /* {file_name} */; }};'
    build_section_end = "/* End PBXBuildFile section */"
    content = content.replace(build_section_end, build_file_entry + "\n" + build_section_end)

    # 2. Add PBXFileReference entry
    file_ref_entry = f'\t\t{file_ref_id} /* {file_name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {file_name}; sourceTree = "<group>"; }};'
    file_ref_end = "/* End PBXFileReference section */"
    content = content.replace(file_ref_end, file_ref_entry + "\n" + file_ref_end)

    # 3. Add file to GroupChat/Views group (2F4594B2B14AE664BBCA5220)
    # Find the Views group and add our file after GroupChatView.swift
    group_pattern = r'(2F4594B2B14AE664BBCA5220 /\* Views \*/ = \{[\s\S]*?children = \(\s*c305a0ac26e55adeed024b77 /\* GroupChatView\.swift \*/,)'
    replacement = rf'\g<1>\n\t\t\t\t{file_ref_id} /* {file_name} */,'
    content = re.sub(group_pattern, replacement, content)

    # 4. Add to PBXSourcesBuildPhase
    # Find the Sources build phase and add our file
    sources_phase_pattern = r'(files = \(\s*\n)(\t\t\t\t[A-Z0-9_]+ /\* .+\.swift in Sources \*/,)'
    sources_insert = f'\t\t\t\t{build_file_id} /* {file_name} in Sources */,\n'
    content = re.sub(sources_phase_pattern, rf'\g<1>{sources_insert}\g<2>', content, count=1)

    return content

def main():
    pbxproj_path = "/Users/proerror/Documents/nova/ios/NovaSocial/ICERED.xcodeproj/project.pbxproj"

    print("Reading project.pbxproj...")
    content = read_file(pbxproj_path)

    # Check if file is already added
    if "STARTGROUPCHAT_REF" in content:
        print("StartGroupChatView.swift already added to project. Exiting.")
        return

    print("Adding StartGroupChatView.swift to Xcode project...")
    modified_content = add_to_pbxproj(content)

    print("Writing modified project.pbxproj...")
    write_file(pbxproj_path, modified_content)

    print("Done! StartGroupChatView.swift added to Features/GroupChat/Views/")

if __name__ == "__main__":
    main()
