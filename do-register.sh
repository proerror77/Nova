#!/bin/bash
curl -s -X POST "http://a3326508b1e3c43239348cac7ce9ee03-1036729988.ap-northeast-1.elb.amazonaws.com/api/v2/auth/register" \
  -H "Content-Type: application/json" \
  -d @/Users/proerror/Documents/nova/register-payload.json
