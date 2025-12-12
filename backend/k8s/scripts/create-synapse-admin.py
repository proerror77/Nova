#!/usr/bin/env python3
"""
Create Synapse Admin User Script

This script creates an admin user in Synapse using the registration shared secret.
The admin user can then be used to obtain an access token for the Synapse Admin API.

Usage:
    python3 create-synapse-admin.py --homeserver https://matrix.staging.nova.app --secret YOUR_SECRET

Environment Variables:
    SYNAPSE_HOMESERVER_URL - Homeserver URL (default: https://matrix.staging.nova.app)
    REGISTRATION_SHARED_SECRET - Registration shared secret from synapse-oidc-secrets
"""

import argparse
import hmac
import hashlib
import json
import requests
import secrets
import sys
import os


def generate_mac(nonce: str, username: str, password: str, admin: bool, shared_secret: str) -> str:
    """
    Generate HMAC for user registration.

    Args:
        nonce: Random nonce
        username: Username to register
        password: Password for the user
        admin: Whether the user should be an admin
        shared_secret: Registration shared secret

    Returns:
        HMAC hexdigest
    """
    mac = hmac.new(
        key=shared_secret.encode('utf-8'),
        digestmod=hashlib.sha1,
    )

    mac.update(nonce.encode('utf-8'))
    mac.update(b"\x00")
    mac.update(username.encode('utf-8'))
    mac.update(b"\x00")
    mac.update(password.encode('utf-8'))
    mac.update(b"\x00")
    mac.update(b"admin" if admin else b"notadmin")

    return mac.hexdigest()


def register_admin_user(homeserver_url: str, username: str, password: str, shared_secret: str) -> dict:
    """
    Register a new admin user in Synapse.

    Args:
        homeserver_url: Base URL of the homeserver
        username: Username to register
        password: Password for the user
        shared_secret: Registration shared secret

    Returns:
        Response from the registration endpoint
    """
    nonce = secrets.token_hex(16)
    mac = generate_mac(nonce, username, password, admin=True, shared_secret=shared_secret)

    data = {
        "nonce": nonce,
        "username": username,
        "password": password,
        "admin": True,
        "mac": mac
    }

    try:
        response = requests.post(
            f"{homeserver_url}/_synapse/admin/v1/register",
            json=data,
            timeout=10
        )
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        print(f"Error: Failed to register user: {e}", file=sys.stderr)
        sys.exit(1)


def login_user(homeserver_url: str, username: str, password: str) -> dict:
    """
    Login as the user to obtain an access token.

    Args:
        homeserver_url: Base URL of the homeserver
        username: Username to login
        password: Password for the user

    Returns:
        Login response with access token
    """
    data = {
        "type": "m.login.password",
        "identifier": {
            "type": "m.id.user",
            "user": username
        },
        "password": password
    }

    try:
        response = requests.post(
            f"{homeserver_url}/_matrix/client/v3/login",
            json=data,
            timeout=10
        )
        response.raise_for_status()
        return response.json()
    except requests.exceptions.RequestException as e:
        print(f"Error: Failed to login: {e}", file=sys.stderr)
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description="Create a Synapse admin user and obtain access token"
    )
    parser.add_argument(
        "--homeserver",
        default=os.getenv("SYNAPSE_HOMESERVER_URL", "https://matrix.staging.nova.app"),
        help="Homeserver URL (default: from SYNAPSE_HOMESERVER_URL env or https://matrix.staging.nova.app)"
    )
    parser.add_argument(
        "--secret",
        default=os.getenv("REGISTRATION_SHARED_SECRET"),
        help="Registration shared secret (default: from REGISTRATION_SHARED_SECRET env)"
    )
    parser.add_argument(
        "--username",
        default="nova-admin",
        help="Admin username (default: nova-admin)"
    )
    parser.add_argument(
        "--password",
        default=None,
        help="Admin password (default: auto-generated secure password)"
    )
    parser.add_argument(
        "--login",
        action="store_true",
        help="Also login to obtain access token"
    )

    args = parser.parse_args()

    if not args.secret:
        print("Error: Registration shared secret is required", file=sys.stderr)
        print("Provide via --secret or REGISTRATION_SHARED_SECRET environment variable", file=sys.stderr)
        sys.exit(1)

    # Generate secure password if not provided
    password = args.password or secrets.token_urlsafe(32)

    print(f"Creating admin user on {args.homeserver}...")
    print(f"Username: {args.username}")
    print("-" * 60)

    # Register the admin user
    result = register_admin_user(
        homeserver_url=args.homeserver,
        username=args.username,
        password=password,
        shared_secret=args.secret
    )

    print(f"✓ Admin user created successfully!")
    print(f"  User ID: {result.get('user_id', 'N/A')}")
    print(f"  Username: {args.username}")
    print(f"  Password: {password}")
    print()

    # Login to get access token if requested
    if args.login:
        print("Logging in to obtain access token...")
        login_result = login_user(
            homeserver_url=args.homeserver,
            username=args.username,
            password=password
        )

        print(f"✓ Login successful!")
        print(f"  Access Token: {login_result.get('access_token', 'N/A')}")
        print(f"  Device ID: {login_result.get('device_id', 'N/A')}")
        print()

        # Print kubectl command to store the token
        print("To store the access token in Kubernetes, run:")
        print()
        print("kubectl create secret generic synapse-admin-api \\")
        print(f"  --from-literal=SYNAPSE_ADMIN_TOKEN='{login_result.get('access_token')}' \\")
        print("  --from-literal=SYNAPSE_HOMESERVER_URL='http://matrix-synapse:8008' \\")
        print("  --from-literal=SYNAPSE_SERVER_NAME='staging.nova.app' \\")
        print("  --namespace=nova-backend \\")
        print("  --dry-run=client -o yaml | kubectl apply -f -")
        print()

    print("=" * 60)
    print("IMPORTANT: Save these credentials securely!")
    print("=" * 60)


if __name__ == "__main__":
    main()
