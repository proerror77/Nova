#!/usr/bin/env python3
"""
Remove duplicate .into_inner() calls
"""

import re
from pathlib import Path

def remove_duplicate_into_inner(content: str) -> str:
    """Remove duplicate consecutive .into_inner() calls"""
    lines = content.split('\n')
    result = []
    i = 0

    while i < len(lines):
        line = lines[i]

        # Check if this is a .into_inner() call
        if '.into_inner()' in line:
            var_name_match = re.match(r'\s+let (\w+) = \1\.into_inner\(\);', line)
            if var_name_match:
                # This is a valid .into_inner() call, check if next line is duplicate
                result.append(line)
                i += 1

                # Skip duplicate lines
                while i < len(lines) and lines[i].strip() == line.strip():
                    i += 1
                continue

        result.append(line)
        i += 1

    return '\n'.join(result)

def process_file(file_path: Path) -> bool:
    """Process a single file"""
    content = file_path.read_text()
    original = content

    new_content = remove_duplicate_into_inner(content)

    if new_content != original:
        file_path.write_text(new_content)
        print(f"✅ Cleaned: {file_path.name}")
        return True

    return False

def main():
    messaging_dir = Path("/Users/proerror/Documents/nova/backend/messaging-service")
    routes_dir = messaging_dir / "src" / "routes"

    total_fixed = 0
    for rs_file in routes_dir.glob("*.rs"):
        if process_file(rs_file):
            total_fixed += 1

    print(f"\n📊 Total files cleaned: {total_fixed}")

if __name__ == "__main__":
    main()
