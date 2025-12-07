#!/usr/bin/env python3
"""
Script to add missing Swift files to Xcode project.pbxproj

Files to add:
1. WriteView.swift -> Features/CreatePost/Views/
2. DeviceModels.swift -> Shared/Models/User/
3. DeviceService.swift -> Shared/Services/User/
4. FriendsService.swift -> Shared/Services/Friends/ (new group)
"""

import re
import uuid

def generate_xcode_id():
    """Generate a 24-character hex ID like Xcode uses"""
    return uuid.uuid4().hex[:24].upper()

# Define files to add with their IDs
files_to_add = [
    {
        "name": "WriteView.swift",
        "file_ref_id": "WRITEVIEW_FILEREF01",
        "build_file_id": "WRITEVIEW_BUILD001",
        "group_id": "95DA8974C80C226E0EEFD27B",  # CreatePost/Views group
        "path": "WriteView.swift"
    },
    {
        "name": "DeviceModels.swift",
        "file_ref_id": "DEVICEMODELS_REF01",
        "build_file_id": "DEVICEMODELS_BLD01",
        "group_id": "82E3D0A6EE1F48B21B595A43",  # Shared/Models/User group
        "path": "DeviceModels.swift"
    },
    {
        "name": "DeviceService.swift",
        "file_ref_id": "DEVICESERVICE_REF1",
        "build_file_id": "DEVICESERVICE_BLD1",
        "group_id": "1F229D0385FF3AA68655E53A",  # Shared/Services/User group
        "path": "DeviceService.swift"
    },
]

# Friends group needs to be created
friends_group_id = "FRIENDSSERVICEGROUP"
friends_service_file = {
    "name": "FriendsService.swift",
    "file_ref_id": "FRIENDSSERVICE_REF1",
    "build_file_id": "FRIENDSSERVICE_BLD1",
    "group_id": friends_group_id,
    "path": "FriendsService.swift"
}

def read_file(path):
    with open(path, 'r') as f:
        return f.read()

def write_file(path, content):
    with open(path, 'w') as f:
        f.write(content)

def add_to_pbxproj(content):
    # 1. Add PBXBuildFile entries (before "/* End PBXBuildFile section */")
    build_file_entries = []
    for f in files_to_add + [friends_service_file]:
        entry = f'\t\t{f["build_file_id"]} /* {f["name"]} in Sources */ = {{isa = PBXBuildFile; fileRef = {f["file_ref_id"]} /* {f["name"]} */; }};'
        build_file_entries.append(entry)

    build_section_end = "/* End PBXBuildFile section */"
    build_insert = "\n".join(build_file_entries) + "\n"
    content = content.replace(build_section_end, build_insert + build_section_end)

    # 2. Add PBXFileReference entries (before "/* End PBXFileReference section */")
    file_ref_entries = []
    for f in files_to_add + [friends_service_file]:
        entry = f'\t\t{f["file_ref_id"]} /* {f["name"]} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {f["name"]}; sourceTree = "<group>"; }};'
        file_ref_entries.append(entry)

    file_ref_end = "/* End PBXFileReference section */"
    file_ref_insert = "\n".join(file_ref_entries) + "\n"
    content = content.replace(file_ref_end, file_ref_insert + file_ref_end)

    # 3. Add files to their respective groups
    # Add WriteView.swift to CreatePost/Views group (95DA8974C80C226E0EEFD27B)
    createpost_views_pattern = r'(95DA8974C80C226E0EEFD27B /\* Views \*/ = \{[\s\S]*?children = \(\s*)'
    content = re.sub(
        createpost_views_pattern,
        r'\g<1>WRITEVIEW_FILEREF01 /* WriteView.swift */,\n\t\t\t\t',
        content
    )

    # Add DeviceModels.swift to Shared/Models/User group (82E3D0A6EE1F48B21B595A43)
    models_user_pattern = r'(82E3D0A6EE1F48B21B595A43 /\* User \*/ = \{[\s\S]*?children = \(\s*)'
    content = re.sub(
        models_user_pattern,
        r'\g<1>DEVICEMODELS_REF01 /* DeviceModels.swift */,\n\t\t\t\t',
        content
    )

    # Add DeviceService.swift to Shared/Services/User group (1F229D0385FF3AA68655E53A)
    services_user_pattern = r'(1F229D0385FF3AA68655E53A /\* User \*/ = \{[\s\S]*?children = \(\s*)'
    content = re.sub(
        services_user_pattern,
        r'\g<1>DEVICESERVICE_REF1 /* DeviceService.swift */,\n\t\t\t\t',
        content
    )

    # 4. Create Friends group and add FriendsService.swift
    # First create the group definition (add before "/* End PBXGroup section */")
    friends_group_def = f'''\t\t{friends_group_id} /* Friends */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{friends_service_file["file_ref_id"]} /* FriendsService.swift */,
\t\t\t);
\t\t\tpath = Friends;
\t\t\tsourceTree = "<group>";
\t\t}};
'''
    group_section_end = "/* End PBXGroup section */"
    content = content.replace(group_section_end, friends_group_def + group_section_end)

    # Add Friends group to Services group (C652DC05CDF0383A5C43BEC2)
    services_group_pattern = r'(C652DC05CDF0383A5C43BEC2 /\* Services \*/ = \{[\s\S]*?children = \(\s*)'
    content = re.sub(
        services_group_pattern,
        rf'\g<1>{friends_group_id} /* Friends */,\n\t\t\t\t',
        content
    )

    # 5. Add to PBXSourcesBuildPhase (Sources build phase)
    # Find the Sources build phase and add our files
    sources_entries = []
    for f in files_to_add + [friends_service_file]:
        entry = f'\t\t\t\t{f["build_file_id"]} /* {f["name"]} in Sources */,'
        sources_entries.append(entry)

    # Find the Sources build phase files section
    # Pattern: look for the build phase that has "Sources" in comments
    sources_phase_pattern = r'(files = \(\s*\n)(\t\t\t\t[A-Z0-9_]+ /\* .+\.swift in Sources \*/,)'
    sources_insert = "\n".join(sources_entries) + "\n"

    # Insert after first swift file in sources
    content = re.sub(
        sources_phase_pattern,
        rf'\g<1>{sources_insert}\g<2>',
        content,
        count=1
    )

    return content

def main():
    pbxproj_path = "/Users/proerror/Documents/nova/ios/NovaSocial/ICERED.xcodeproj/project.pbxproj"

    print("Reading project.pbxproj...")
    content = read_file(pbxproj_path)

    # Check if files are already added
    if "WRITEVIEW_FILEREF01" in content:
        print("Files already added to project. Exiting.")
        return

    print("Adding missing files to Xcode project...")
    modified_content = add_to_pbxproj(content)

    print("Writing modified project.pbxproj...")
    write_file(pbxproj_path, modified_content)

    print("Done! Files added:")
    print("  - WriteView.swift -> Features/CreatePost/Views/")
    print("  - DeviceModels.swift -> Shared/Models/User/")
    print("  - DeviceService.swift -> Shared/Services/User/")
    print("  - FriendsService.swift -> Shared/Services/Friends/ (new group)")

if __name__ == "__main__":
    main()
