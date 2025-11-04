#!/usr/bin/env python3
"""
Complete fix for remaining messaging-service handler files.
Applies Axum → Actix transformations.
"""
import re
from pathlib import Path

MESSAGING_ROOT = Path('backend/messaging-service/src')

# Files that still need fixing
FILES_TO_FIX = [
    'routes/reactions.rs',
    'routes/locations.rs',
    'routes/key_exchange.rs',
    'routes/notifications.rs',
    'routes/attachments.rs',
    'websocket/events.rs',
    'websocket/streams.rs',
    'handlers/websocket_offline.rs',
]

def apply_fixes(content: str) -> str:
    """Apply all Axum → Actix transformations."""

    # 1. Remove axum imports
    content = re.sub(r'use axum::extract::[^;]+;?\n', '', content)
    content = re.sub(r'use axum::response::[^;]+;?\n', '', content)
    content = re.sub(r'use axum::http::[^;]+;?\n', '', content)
    content = re.sub(r'use axum::[^;]+;?\n', '', content)

    # 2. Add actix-web imports if not present
    if 'use actix_web::' not in content:
        # Find the last use statement
        use_lines = list(re.finditer(r'^use [^;]+;\n', content, re.MULTILINE))
        if use_lines:
            insert_pos = use_lines[-1].end()
            actix_import = 'use actix_web::{web, HttpResponse, Error};\n'
            content = content[:insert_pos] + actix_import + content[insert_pos:]

    # 3. Fix handler signatures - State<T>
    content = re.sub(
        r'State\(([a-z_]+)\):\s*State<([^>]+)>',
        r'\1: web::Data<\2>',
        content
    )

    # 4. Fix handler signatures - Path<T>
    content = re.sub(
        r'Path\(([a-z_]+)\):\s*Path<([^>]+)>',
        r'\1: web::Path<\2>',
        content
    )

    # 5. Fix handler signatures - Json<T>
    content = re.sub(
        r'Json\(([a-z_]+)\):\s*Json<([^>]+)>',
        r'\1: web::Json<\2>',
        content
    )

    # 6. Fix handler signatures - Query<T>
    content = re.sub(
        r'Query\(([a-z_]+)\):\s*Query<([^>]+)>',
        r'\1: web::Query<\2>',
        content
    )

    # 7. Fix return types - impl IntoResponse
    content = re.sub(
        r'Result<impl IntoResponse,\s*([^>]+)>',
        r'Result<HttpResponse, Error>',
        content
    )
    content = re.sub(
        r'Result<Json<([^>]+)>,\s*([^>]+)>',
        r'Result<HttpResponse, Error>',
        content
    )
    content = re.sub(
        r'Result<StatusCode,\s*([^>]+)>',
        r'Result<HttpResponse, Error>',
        content
    )
    content = re.sub(
        r'Result<\(StatusCode,\s*Json<[^>]+>\),\s*([^>]+)>',
        r'Result<HttpResponse, Error>',
        content
    )

    # 8. Fix return statements - Ok(Json(x))
    content = re.sub(
        r'Ok\(Json\(([^)]+)\)\)',
        r'Ok(HttpResponse::Ok().json(\1))',
        content
    )

    # 9. Fix return statements - Ok((StatusCode::X, Json(x)))
    content = re.sub(
        r'Ok\(\(StatusCode::CREATED,\s*Json\(([^)]+)\)\)\)',
        r'Ok(HttpResponse::Created().json(\1))',
        content
    )
    content = re.sub(
        r'Ok\(\(StatusCode::OK,\s*Json\(([^)]+)\)\)\)',
        r'Ok(HttpResponse::Ok().json(\1))',
        content
    )

    # 10. Fix return statements - Ok(StatusCode::X)
    content = re.sub(
        r'Ok\(StatusCode::CREATED\)',
        r'Ok(HttpResponse::Created().finish())',
        content
    )
    content = re.sub(
        r'Ok\(StatusCode::NO_CONTENT\)',
        r'Ok(HttpResponse::NoContent().finish())',
        content
    )
    content = re.sub(
        r'Ok\(StatusCode::OK\)',
        r'Ok(HttpResponse::Ok().finish())',
        content
    )

    # 11. Add .into_inner() calls for Path extraction
    # This is tricky - we need to add it after parameter binding
    # Pattern: let x = path_param; → let x = path_param.into_inner();
    # But only for web::Path types - we'll do this manually if needed

    return content

def process_file(filepath: Path) -> bool:
    """Process a single file."""
    if not filepath.exists():
        print(f"⚠️  File not found: {filepath}")
        return False

    with open(filepath, 'r') as f:
        original = f.read()

    fixed = apply_fixes(original)

    if fixed != original:
        with open(filepath, 'w') as f:
            f.write(fixed)
        print(f"✅ Fixed: {filepath}")
        return True
    else:
        print(f"⏭️  No changes: {filepath}")
        return False

def main():
    print("🔧 Fixing remaining messaging-service handler files...\n")

    fixed_count = 0
    for file_path in FILES_TO_FIX:
        full_path = MESSAGING_ROOT / file_path
        if process_file(full_path):
            fixed_count += 1

    print(f"\n✅ Fixed {fixed_count}/{len(FILES_TO_FIX)} files")
    print("\n🔍 Next: Run 'cd backend/messaging-service && cargo check'")

if __name__ == '__main__':
    main()
