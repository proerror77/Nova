#!/usr/bin/env python3
import os
import re
from pathlib import Path

# Replacement patterns
replacements = [
    (r'use axum::extract::', 'use actix_web::web::'),
    (r'use axum::http::', 'use actix_web::http::'),
    (r'use axum::response::', 'use actix_web::'),
    (r'axum::extract::State', 'web::Data'),
    (r'axum::extract::Path', 'web::Path'),
    (r'axum::extract::Json', 'web::Json'),
    (r'axum::extract::Query', 'web::Query'),
    (r'axum::http::StatusCode', 'actix_web::http::StatusCode'),
    (r'State<([^>]+)>', r'web::Data<\1>'),
    (r'impl IntoResponse', 'HttpResponse'),
    (r'use axum::response::IntoResponse;', ''),  # Remove unused
]

def process_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()

    original = content
    for pattern, replacement in replacements:
        content = re.sub(pattern, replacement, content)

    if content != original:
        with open(filepath, 'w') as f:
            f.write(content)
        return True
    return False

# Process all .rs files in src/
src_dir = Path('backend/messaging-service/src')
modified_files = []

for rs_file in src_dir.rglob('*.rs'):
    if process_file(rs_file):
        modified_files.append(str(rs_file))

print(f"✅ Modified {len(modified_files)} files:")
for f in modified_files:
    print(f"  - {f}")
