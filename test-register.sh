#!/bin/bash
curl -s -X POST "http://a3326508b1e3c43239348cac7ce9ee03-1036729988.ap-northeast-1.elb.amazonaws.com/api/v2/auth/register" \
  -H "Content-Type: application/json" \
  -d '{"email":"e2etest1732333300@test.com","password":"Pass123","username":"e2etest1732333300","display_name":"E2E Test User"}' | jq '.'
