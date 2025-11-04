#!/usr/bin/env python3
"""
Add .into_inner() calls for all single web::Path<T> parameters.
"""

import re
from pathlib import Path

def add_into_inner_for_single_paths(content: str) -> str:
    """
    Find functions with `var: web::Path<Type>` and add `let var = var.into_inner();`
    """
    lines = content.split('\n')
    result = []
    i = 0

    while i < len(lines):
        line = lines[i]

        # Detect async function start
        if re.search(r'pub\s+async\s+fn\s+\w+|async\s+fn\s+\w+', line):
            # Collect full signature
            sig_lines = [line]
            paren_depth = line.count('(') - line.count(')')
            j = i + 1

            while paren_depth > 0 and j < len(lines):
                sig_lines.append(lines[j])
                paren_depth += lines[j].count('(') - lines[j].count(')')
                j += 1

            full_sig = '\n'.join(sig_lines)

            # Find single Path parameters: var: web::Path<Type>
            # Exclude tuple patterns: path: web::Path<(..., ...)>
            path_params = []
            for match in re.finditer(r'(\w+):\s*web::Path<([^>]+)>', full_sig):
                var_name = match.group(1)
                type_str = match.group(2)

                # Skip if it's a tuple
                if ',' not in type_str:
                    path_params.append(var_name)

            # Write signature
            result.extend(sig_lines)
            i = j

            # Find opening brace
            while i < len(lines) and '{' not in lines[i]:
                result.append(lines[i])
                i += 1

            if i < len(lines):
                result.append(lines[i])  # Line with {
                i += 1

                # Add .into_inner() calls
                if path_params:
                    indent = '    '
                    for var_name in path_params:
                        result.append(f'{indent}let {var_name} = {var_name}.into_inner();')
        else:
            result.append(line)
            i += 1

    return '\n'.join(result)

def process_file(file_path: Path) -> bool:
    """Process a single file"""
    content = file_path.read_text()
    original = content

    new_content = add_into_inner_for_single_paths(content)

    if new_content != original:
        file_path.write_text(new_content)
        print(f"✅ Fixed: {file_path.name}")
        return True

    return False

def main():
    messaging_dir = Path("/Users/proerror/Documents/nova/backend/messaging-service")
    routes_dir = messaging_dir / "src" / "routes"

    target_files = [
        "notifications.rs",
        "attachments.rs",
    ]

    total_fixed = 0
    for filename in target_files:
        file_path = routes_dir / filename
        if file_path.exists():
            if process_file(file_path):
                total_fixed += 1

    print(f"\n📊 Total files fixed: {total_fixed}")

if __name__ == "__main__":
    main()
