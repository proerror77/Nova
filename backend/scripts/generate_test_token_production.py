#!/usr/bin/env python3
"""
Generate a test JWT token using PRODUCTION keys from staging environment
This script generates tokens that will work with the deployed feed-service
"""

import jwt
import uuid
import os
from datetime import datetime, timedelta
from pathlib import Path

def load_production_keys():
    """Load production JWT keys from PEM files"""
    script_dir = Path(__file__).parent
    private_key_path = script_dir / "production-jwt-private.pem"
    public_key_path = script_dir / "production-jwt-public.pem"

    if not private_key_path.exists():
        raise FileNotFoundError(
            f"Production private key not found at {private_key_path}\n"
            "Run: kubectl get secret nova-jwt-keys -n nova-staging -o jsonpath='{.data.JWT_PRIVATE_KEY_PEM}' | base64 -d > backend/scripts/production-jwt-private.pem"
        )

    if not public_key_path.exists():
        raise FileNotFoundError(
            f"Production public key not found at {public_key_path}\n"
            "Run: kubectl get secret nova-jwt-keys -n nova-staging -o jsonpath='{.data.JWT_PUBLIC_KEY_PEM}' | base64 -d > backend/scripts/production-jwt-public.pem"
        )

    with open(private_key_path, 'r') as f:
        private_key = f.read()

    with open(public_key_path, 'r') as f:
        public_key = f.read()

    return private_key, public_key

def generate_test_token(user_id=None, email=None, username=None, expiry_hours=24):
    """
    Generate a test JWT token using production keys

    Args:
        user_id: User UUID (default: test UUID)
        email: User email (default: test@nova.com)
        username: Username (default: test_user)
        expiry_hours: Token expiry in hours (default: 24)
    """
    # Load production keys
    print("📦 Loading production JWT keys...")
    try:
        private_key, public_key = load_production_keys()
        print("✅ Production keys loaded successfully")
    except FileNotFoundError as e:
        print(f"❌ Error: {e}")
        return None

    # Default values
    if not user_id:
        user_id = "00000000-0000-0000-0000-000000000001"
    if not email:
        email = "test@nova.com"
    if not username:
        username = "test_user"

    # Current time
    now = datetime.utcnow()
    expiry = now + timedelta(hours=expiry_hours)

    # Create claims matching feed-service expectations
    claims = {
        "sub": user_id,           # Subject (user ID)
        "iat": int(now.timestamp()),       # Issued at
        "exp": int(expiry.timestamp()),    # Expiration
        "nbf": int(now.timestamp()),       # Not before
        "token_type": "access",   # Token type
        "email": email,           # User email
        "username": username,     # Username
        "jti": str(uuid.uuid4())  # JWT ID (unique identifier)
    }

    # Generate token using production private key
    print("\n🔐 Generating JWT token...")
    token = jwt.encode(
        claims,
        private_key,
        algorithm="RS256"
    )

    # Verify token with public key
    try:
        decoded = jwt.decode(
            token,
            public_key,
            algorithms=["RS256"]
        )
        print("✅ Token generated and verified successfully")
    except Exception as e:
        print(f"❌ Token verification failed: {e}")
        return None

    # Display token info
    print("\n" + "="*60)
    print("✅ PRODUCTION TEST JWT TOKEN")
    print("="*60)
    print("\n📋 Token:")
    print(token)
    print("\n📊 Token Details:")
    print(f"  User ID:   {user_id}")
    print(f"  Email:     {email}")
    print(f"  Username:  {username}")
    print(f"  Issued:    {now}")
    print(f"  Expires:   {expiry} ({expiry_hours} hours from now)")
    print(f"  JWT ID:    {claims['jti']}")

    print("\n🔧 Usage in iOS:")
    print(f'  APIClient.shared.setAuthToken("{token}")')

    print("\n🧪 Usage with curl:")
    print(f'  curl -H "Authorization: Bearer {token}" \\')
    print(f'       http://a3326508b1e3c43239348cac7ce9ee03-1036729988.ap-northeast-1.elb.amazonaws.com/api/v2/feed')

    print("\n" + "="*60)

    return token

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description="Generate JWT token using production keys from staging"
    )
    parser.add_argument(
        "--user-id",
        help="User UUID (default: test UUID)",
        default=None
    )
    parser.add_argument(
        "--email",
        help="User email (default: test@nova.com)",
        default=None
    )
    parser.add_argument(
        "--username",
        help="Username (default: test_user)",
        default=None
    )
    parser.add_argument(
        "--expiry-hours",
        type=int,
        help="Token expiry in hours (default: 24)",
        default=24
    )

    args = parser.parse_args()

    token = generate_test_token(
        user_id=args.user_id,
        email=args.email,
        username=args.username,
        expiry_hours=args.expiry_hours
    )

    if token:
        # Save to file for easy reuse
        with open('/tmp/test-jwt-token.txt', 'w') as f:
            f.write(token)
        print(f"\n💾 Token saved to: /tmp/test-jwt-token.txt")
