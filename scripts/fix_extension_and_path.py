#!/usr/bin/env python3
"""
Fix remaining Axum-specific patterns:
1. Extension<T> → HttpRequest + extensions()
2. Path((a, b)): Path<...> → path: web::Path<...>
3. Json(...) → web::Json(...)
"""

import re
from pathlib import Path

def fix_file_content(content: str, filename: str) -> str:
    """Fix all patterns in a single file"""

    # Pattern 1: Fix Extension extractor
    # Extension(var): Extension<Type> → Add HttpRequest param + extract from it
    # This is complex, so we'll transform to use User guard instead

    # For reactions.rs: Extension(requesting_user_id): Extension<Uuid>
    # → user: User, then use user.id
    if "Extension(requesting_user_id): Extension<Uuid>" in content:
        content = content.replace(
            "Extension(requesting_user_id): Extension<Uuid>",
            "user: User"
        )
        content = content.replace("requesting_user_id", "user.id")

    # Pattern 2: Fix Path destructuring
    # Path((a, b)): Path<(T, U)> → path: web::Path<(T, U)>
    def replace_path_destruct(match):
        vars = match.group(1)
        type_sig = match.group(2)
        return f"path: web::Path<({type_sig})>"

    content = re.sub(
        r'Path\((\([^)]+\))\):\s*Path<\(([^)]+)\)>',
        replace_path_destruct,
        content
    )

    # Pattern 3: Ensure web imports exist
    # Check imports at top of file
    if 'use actix_web::{' in content:
        # Check if web is in the import list
        import_match = re.search(r'use actix_web::\{([^}]+)\}', content)
        if import_match:
            imports = import_match.group(1)
            if 'web' not in imports:
                # Add web to imports
                new_imports = imports.rstrip() + ', web'
                content = content.replace(
                    f'use actix_web::{{{imports}}}',
                    f'use actix_web::{{{new_imports}}}'
                )

    return content

def process_file(file_path: Path) -> bool:
    """Process a single file"""
    content = file_path.read_text()
    original = content

    new_content = fix_file_content(content, file_path.name)

    if new_content != original:
        file_path.write_text(new_content)
        print(f"✅ Fixed: {file_path.name}")
        return True

    return False

def main():
    messaging_dir = Path("/Users/proerror/Documents/nova/backend/messaging-service")
    routes_dir = messaging_dir / "src" / "routes"

    target_files = [
        "reactions.rs",
        "attachments.rs",
        "notifications.rs",
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
