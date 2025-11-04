#!/usr/bin/env python3
import os
import re
from pathlib import Path

files_to_fix = [
    'backend/messaging-service/src/middleware/guards.rs',
    'backend/messaging-service/src/websocket/handlers.rs',
    'backend/messaging-service/src/routes/groups.rs',
    'backend/messaging-service/src/routes/reactions.rs',
    'backend/messaging-service/src/routes/locations.rs',
    'backend/messaging-service/src/routes/conversations.rs',
    'backend/messaging-service/src/routes/calls.rs',
    'backend/messaging-service/src/routes/key_exchange.rs',
    'backend/messaging-service/src/routes/rtc.rs',
    'backend/messaging-service/src/routes/notifications.rs',
    'backend/messaging-service/src/routes/messages.rs',
    'backend/messaging-service/src/routes/attachments.rs',
    'backend/messaging-service/src/handlers/websocket_offline.rs',
]

def fix_file(filepath):
    if not os.path.exists(filepath):
        print(f"⚠️  File not found: {filepath}")
        return False

    with open(filepath, 'r') as f:
        content = f.read()

    original = content

    # Remove all axum imports
    content = re.sub(r'use axum::.*?;\n', '', content)

    # Add actix-web imports if handler functions exist
    if 'async fn' in content and 'web::' not in content:
        # Add at the top after other imports
        import_section = 'use actix_web::{web, HttpResponse, Error, HttpRequest};\n'
        # Find the last 'use' statement
        matches = list(re.finditer(r'^use .*?;\n', content, re.MULTILINE))
        if matches:
            last_use_end = matches[-1].end()
            content = content[:last_use_end] + import_section + content[last_use_end:]

    # Fix HeaderMap (actix uses http::HeaderMap, not actix_web::http::HeaderMap)
    content = re.sub(r'actix_web::http::HeaderMap', 'http::HeaderMap', content)
    content = re.sub(r'use actix_web::http::HeaderMap;', 'use http::HeaderMap;', content)

    # Fix remaining IntoResponse patterns
    content = re.sub(r'impl IntoResponse', 'HttpResponse', content)
    content = re.sub(r'-> impl IntoResponse', '-> Result<HttpResponse, Error>', content)

    # Fix Response types
    content = re.sub(r': Response\b', ': HttpResponse', content)

    if content != original:
        with open(filepath, 'w') as f:
            f.write(content)
        return True
    return False

modified = 0
for filepath in files_to_fix:
    if fix_file(filepath):
        print(f"✅ Fixed: {filepath}")
        modified += 1
    else:
        print(f"⏭️  Skipped: {filepath}")

print(f"\n✅ Modified {modified}/{len(files_to_fix)} files")
