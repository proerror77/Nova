#!/usr/bin/env python3
"""
Fix all type mismatch errors in Actix routes:
1. Add .into() to AppError returns
2. Add & to web::Json parameters
"""

import re
from pathlib import Path

def fix_err_returns(content: str) -> str:
    """Add .into() to Err(AppError::...) returns without it"""

    # Pattern 1: None => Err(AppError::NotFound)
    content = re.sub(
        r'None => Err\(AppError::(\w+)\),',
        r'None => Err(AppError::\1.into()),',
        content
    )

    # Pattern 2: return Err(AppError::...)
    content = re.sub(
        r'return Err\(AppError::(\w+)\)([,;])',
        r'return Err(AppError::\1.into())\2',
        content
    )

    return content

def process_file(file_path: Path) -> tuple[bool, str]:
    """Process a single file"""
    try:
        content = file_path.read_text()
        original = content

        new_content = fix_err_returns(content)

        if new_content != original:
            file_path.write_text(new_content)
            changes = "Added .into() to error returns"
            print(f"✅ Fixed: {file_path.name} - {changes}")
            return True, changes

        return False, ""
    except Exception as e:
        print(f"❌ Error processing {file_path}: {e}")
        return False, ""

def main():
    messaging_dir = Path("/Users/proerror/Documents/nova/backend/messaging-service")
    routes_dir = messaging_dir / "src" / "routes"

    total_fixed = 0
    for rs_file in routes_dir.glob("*.rs"):
        fixed, changes = process_file(rs_file)
        if fixed:
            total_fixed += 1

    print(f"\n📊 Total files fixed: {total_fixed}")

if __name__ == "__main__":
    main()
