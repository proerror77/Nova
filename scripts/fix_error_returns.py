#!/usr/bin/env python3
"""
Fix AppError returns to convert to actix_web::Error using .into()
"""

import re
from pathlib import Path

def fix_error_returns(content: str) -> str:
    """Add .into() to AppError returns that need conversion"""

    # Pattern: return Err(crate::error::AppError::...) without .into()
    # Replace with: return Err(crate::error::AppError::...into())

    # Match: return Err(crate::error::AppError::VARIANT(...))?;
    # Where ? means optional .into()
    pattern = r'return Err\(crate::error::AppError::(\w+)\(([^)]+)\)\);'
    replacement = r'return Err(crate::error::AppError::\1(\2).into());'

    content = re.sub(pattern, replacement, content)

    # Also fix without crate::error:: prefix
    pattern2 = r'return Err\(AppError::(\w+)\(([^)]+)\)\);'
    replacement2 = r'return Err(AppError::\1(\2).into());'

    content = re.sub(pattern2, replacement2, content)

    return content

def process_file(file_path: Path) -> bool:
    """Process a single file"""
    try:
        content = file_path.read_text()
        original = content

        new_content = fix_error_returns(content)

        if new_content != original:
            file_path.write_text(new_content)
            print(f"✅ Fixed: {file_path.relative_to(file_path.parents[3])}")
            return True

        return False
    except Exception as e:
        print(f"❌ Error processing {file_path}: {e}")
        return False

def main():
    messaging_dir = Path("/Users/proerror/Documents/nova/backend/messaging-service")
    routes_dir = messaging_dir / "src" / "routes"

    total_fixed = 0
    for rs_file in routes_dir.glob("*.rs"):
        if process_file(rs_file):
            total_fixed += 1

    print(f"\n📊 Total files fixed: {total_fixed}")

if __name__ == "__main__":
    main()
