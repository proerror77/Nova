#!/usr/bin/env python3
"""
Generate a test JWT token for Nova staging environment.
Requires: pip install pyjwt cryptography
"""

import jwt
import sys
import json
from datetime import datetime, timedelta

def generate_jwt(user_id: str, private_key_pem: str, expiry_hours: int = 24) -> str:
    """Generate a JWT token for testing."""

    import time
    import uuid
    now_ts = int(time.time())
    payload = {
        "sub": user_id,
        "iss": "nova-graphql-gateway",
        "aud": "nova-api",
        "iat": now_ts,
        "exp": now_ts + (expiry_hours * 3600),
        "nbf": now_ts,
        "token_type": "access",
        "email": "test@example.com",
        "username": "testuser",
        "jti": str(uuid.uuid4()),
    }

    token = jwt.encode(
        payload,
        private_key_pem,
        algorithm="RS256"
    )

    return token

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: generate-test-jwt.py <user_id> <private_key_pem_file>")
        print("Example: generate-test-jwt.py 31ba2bad-cd31-43d0-b5b2-2f5ea2f4e31a /tmp/jwt_private_key.pem")
        sys.exit(1)

    user_id = sys.argv[1]
    private_key_file = sys.argv[2]

    with open(private_key_file, 'r') as f:
        private_key_pem = f.read()

    token = generate_jwt(user_id, private_key_pem)
    print(token)
