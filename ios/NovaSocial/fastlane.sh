#!/bin/bash
# Fastlane wrapper script for ICERED
# Usage: ./fastlane.sh <lane> [options]
# Example: ./fastlane.sh beta
#          ./fastlane.sh testflight_upload changelog:"New feature"

cd "$(dirname "$0")"
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
bundle _2.5.23_ exec fastlane "$@"
