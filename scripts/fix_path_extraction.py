#!/usr/bin/env python3
"""
Fix Path<T> extraction issues in Actix-Web handlers.

In Actix, Path<T> needs explicit extraction via .into_inner() or destructuring.
Common patterns:
    Path(id): web::Path<Uuid>  → id: web::Path<Uuid> + let id = id.into_inner();
    Path((a, b)): web::Path<(T, U)> → this is actually correct
"""

import re
import sys
from pathlib import Path

def fix_path_in_function(content: str) -> str:
    """
    Fix Path extraction patterns in function signatures and bodies.
    """

    # Pattern 1: Path(single_var): web::Path<Type>
    # Transform to: single_var: web::Path<Type>
    # Then add extraction at function start

    lines = content.split('\n')
    result_lines = []
    i = 0

    while i < len(lines):
        line = lines[i]

        # Check if this is a function signature with Path extraction
        if 'pub async fn' in line or 'async fn' in line:
            # Collect full function signature (may span multiple lines)
            func_lines = [line]
            paren_count = line.count('(') - line.count(')')
            j = i + 1

            while paren_count != 0 and j < len(lines):
                func_lines.append(lines[j])
                paren_count += lines[j].count('(') - lines[j].count(')')
                j += 1

            full_sig = '\n'.join(func_lines)

            # Find Path(var): web::Path<Type> patterns
            path_match = re.search(r'Path\((\w+)\):\s*web::Path<([^>]+)>', full_sig)

            if path_match:
                var_name = path_match.group(1)
                type_name = path_match.group(2)

                # Replace in signature: Path(var) → var
                new_sig = re.sub(
                    r'Path\(' + var_name + r'\):\s*web::Path<',
                    var_name + ': web::Path<',
                    full_sig
                )

                # Write modified signature
                result_lines.extend(new_sig.split('\n'))

                # Skip the lines we've already processed
                i = j

                # Now find the opening brace of function body
                while i < len(lines) and '{' not in lines[i]:
                    result_lines.append(lines[i])
                    i += 1

                if i < len(lines):
                    result_lines.append(lines[i])  # The line with {
                    i += 1

                    # Add extraction statement
                    # Determine indentation
                    indent = '    '
                    result_lines.append(f'{indent}let {var_name} = {var_name}.into_inner();')
            else:
                result_lines.append(line)
                i += 1
        else:
            result_lines.append(line)
            i += 1

    return '\n'.join(result_lines)

def process_file(file_path: Path):
    """Process a single Rust file"""
    content = file_path.read_text()
    original = content

    # Apply fixes
    content = fix_path_in_function(content)

    if content != original:
        file_path.write_text(content)
        print(f"✅ Fixed: {file_path}")
        return True
    return False

def main():
    messaging_dir = Path("/Users/proerror/Documents/nova/backend/messaging-service")

    # Target directories
    routes_dir = messaging_dir / "src" / "routes"
    handlers_dir = messaging_dir / "src" / "handlers"

    total_fixed = 0

    for directory in [routes_dir, handlers_dir]:
        if not directory.exists():
            continue

        for rs_file in directory.glob("*.rs"):
            if process_file(rs_file):
                total_fixed += 1

    print(f"\n📊 Total files fixed: {total_fixed}")

if __name__ == "__main__":
    main()
