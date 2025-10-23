#!/bin/bash
# Search Service API Test Script

BASE_URL="http://localhost:8081"

echo "=================================="
echo "Search Service API Test"
echo "=================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Test health endpoint
echo -e "${BLUE}1. Testing Health Endpoint${NC}"
echo "GET $BASE_URL/health"
curl -s "$BASE_URL/health"
echo -e "\n"

# Test search users
echo -e "${BLUE}2. Testing User Search${NC}"
echo "GET $BASE_URL/api/v1/search/users?q=test&limit=5"
curl -s "$BASE_URL/api/v1/search/users?q=test&limit=5" | jq '.'
echo ""

# Test search posts
echo -e "${BLUE}3. Testing Post Search${NC}"
echo "GET $BASE_URL/api/v1/search/posts?q=hello&limit=5"
curl -s "$BASE_URL/api/v1/search/posts?q=hello&limit=5" | jq '.'
echo ""

# Test search hashtags
echo -e "${BLUE}4. Testing Hashtag Search${NC}"
echo "GET $BASE_URL/api/v1/search/hashtags?q=tech&limit=5"
curl -s "$BASE_URL/api/v1/search/hashtags?q=tech&limit=5" | jq '.'
echo ""

# Test empty query
echo -e "${BLUE}5. Testing Empty Query (should return all, limited)${NC}"
echo "GET $BASE_URL/api/v1/search/users?limit=3"
curl -s "$BASE_URL/api/v1/search/users?limit=3" | jq '.'
echo ""

echo -e "${GREEN}=================================="
echo "All tests completed!"
echo "==================================${NC}"
