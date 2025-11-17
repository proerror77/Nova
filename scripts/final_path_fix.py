#!/usr/bin/env python3
"""
Comprehensive Path extraction fix for all messaging-service routes.

Adds `let var = var.into_inner();` statements after function signatures
that have `var: web::Path<Type>` parameters.
"""

import re
from pathlib import Path
from typing import List, Tuple

def find_path_params(func_sig: str) -> List[Tuple[str, str]]:
    """
    Find all Path parameters in a function signature.
    Returns list of (var_name, type_name) tuples.

    Examples:
        conversation_id: web::Path<Uuid> → ("conversation_id", "Uuid")
        path: web::Path<(Uuid, Uuid)> → ("path", "(Uuid, Uuid)")
    """
    pattern = r'(\w+):\s*web::Path<([^>]+)>'
    matches = re.findall(pattern, func_sig)
    return matches

def process_rust_file(content: str) -> str:
    """Process entire file and add .into_inner() calls where needed"""

    lines = content.split('\n')
    result = []
    i = 0

    while i < len(lines):
        line = lines[i]

        # Detect function start
        if re.search(r'pub\s+async\s+fn\s+\w+', line) or re.search(r'async\s+fn\s+\w+', line):
            # Collect full function signature
            func_lines = [line]
            brace_depth = line.count('(') - line.count(')')
            j = i + 1

            # Continue until we find matching braces
            while brace_depth > 0 and j < len(lines):
                func_lines.append(lines[j])
                brace_depth += lines[j].count('(') - lines[j].count(')')
                j += 1

            full_sig = '\n'.join(func_lines)

            # Find Path parameters
            path_params = find_path_params(full_sig)

            # Write function signature as-is
            result.extend(func_lines)
            i = j

            # Find the opening brace
            while i < len(lines) and '{' not in lines[i]:
                result.append(lines[i])
                i += 1

            if i < len(lines):
                result.append(lines[i])  # Line with {
                i += 1

                # Add extraction statements for each Path parameter
                if path_params:
                    indent = '    '
                    for var_name, type_str in path_params:
                        # Handle tuple destructuring: (a, b)
                        if type_str.startswith('(') and type_str.endswith(')'):
                            result.append(f'{indent}let {var_name} = {var_name}.into_inner();')
                        else:
                            result.append(f'{indent}let {var_name} = {var_name}.into_inner();')
        else:
            result.append(line)
            i += 1

    return '\n'.join(result)

def process_file(file_path: Path) -> bool:
    """Process a single file"""
    content = file_path.read_text()
    original = content

    new_content = process_rust_file(content)

    if new_content != original:
        file_path.write_text(new_content)
        print(f"✅ Fixed: {file_path.name}")
        return True

    return False

def main():
    messaging_dir = Path("/Users/proerror/Documents/nova/backend/messaging-service")
    routes_dir = messaging_dir / "src" / "routes"

    files_to_fix = [
        "locations.rs",
        "reactions.rs",
        "key_exchange.rs",
        "notifications.rs",
        "attachments.rs",
    ]

    total_fixed = 0
    for filename in files_to_fix:
        file_path = routes_dir / filename
        if file_path.exists():
            if process_file(file_path):
                total_fixed += 1

    print(f"\n📊 Total files fixed: {total_fixed}")

if __name__ == "__main__":
    main()
