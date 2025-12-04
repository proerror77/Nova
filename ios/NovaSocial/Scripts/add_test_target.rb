#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to add Unit Test target to ICERED.xcodeproj
# Usage: ruby add_test_target.rb
#
# This script uses xcodeproj gem to properly add a test target
# Install: gem install xcodeproj

require 'xcodeproj'
require 'securerandom'

PROJECT_PATH = File.expand_path('../ICERED.xcodeproj', __dir__)
TESTS_PATH = File.expand_path('../Tests/UnitTests', __dir__)
TARGET_NAME = 'ICEREDTests'
MAIN_TARGET_NAME = 'ICERED'

def main
  puts "Opening project: #{PROJECT_PATH}"
  project = Xcodeproj::Project.open(PROJECT_PATH)

  # Check if test target already exists
  if project.targets.any? { |t| t.name == TARGET_NAME }
    puts "Test target '#{TARGET_NAME}' already exists. Skipping creation."
    return
  end

  # Find main target
  main_target = project.targets.find { |t| t.name == MAIN_TARGET_NAME }
  unless main_target
    puts "Error: Main target '#{MAIN_TARGET_NAME}' not found"
    exit 1
  end

  puts "Creating test target: #{TARGET_NAME}"

  # Create test target
  test_target = project.new_target(
    :unit_test_bundle,
    TARGET_NAME,
    :ios,
    '17.0'
  )

  # Set bundle identifier
  test_target.build_configurations.each do |config|
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.nova.social.tests'
    config.build_settings['SWIFT_VERSION'] = '5.0'
    config.build_settings['TEST_HOST'] = "$(BUILT_PRODUCTS_DIR)/#{MAIN_TARGET_NAME}.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/#{MAIN_TARGET_NAME}"
    config.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
    config.build_settings['INFOPLIST_FILE'] = 'Tests/UnitTests/Info.plist'
    config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
    config.build_settings['DEVELOPMENT_TEAM'] = main_target.build_configurations.first.build_settings['DEVELOPMENT_TEAM']
  end

  # Add target dependency
  test_target.add_dependency(main_target)

  # Create test group
  tests_group = project.main_group.find_subpath('Tests', true)
  tests_group.set_source_tree('<group>')
  tests_group.set_path('Tests')

  unit_tests_group = tests_group.find_subpath('UnitTests', true)
  unit_tests_group.set_source_tree('<group>')
  unit_tests_group.set_path('UnitTests')

  # Add subgroups
  mocks_group = unit_tests_group.find_subpath('Mocks', true)
  mocks_group.set_source_tree('<group>')
  mocks_group.set_path('Mocks')

  networking_group = unit_tests_group.find_subpath('Networking', true)
  networking_group.set_source_tree('<group>')
  networking_group.set_path('Networking')

  services_group = unit_tests_group.find_subpath('Services', true)
  services_group.set_source_tree('<group>')
  services_group.set_path('Services')

  # Add test files
  test_files = [
    { path: 'Mocks/MockURLProtocol.swift', group: mocks_group },
    { path: 'Mocks/TestFixtures.swift', group: mocks_group },
    { path: 'Networking/APIClientTests.swift', group: networking_group },
    { path: 'Networking/ErrorHandlingTests.swift', group: networking_group },
    { path: 'Services/AuthenticationManagerTests.swift', group: services_group },
    { path: 'Services/IdentityServiceTests.swift', group: services_group },
    { path: 'Info.plist', group: unit_tests_group }
  ]

  test_files.each do |file_info|
    full_path = File.join(TESTS_PATH, file_info[:path])
    next unless File.exist?(full_path)

    file_name = File.basename(file_info[:path])
    file_ref = file_info[:group].new_file(file_name)

    # Add to build phase (except Info.plist)
    unless file_name.end_with?('.plist')
      test_target.source_build_phase.add_file_reference(file_ref)
    end

    puts "  Added: #{file_info[:path]}"
  end

  # Save project
  project.save
  puts "\n✅ Test target '#{TARGET_NAME}' created successfully!"
  puts "\nNext steps:"
  puts "1. Open ICERED.xcodeproj in Xcode"
  puts "2. Select the ICEREDTests scheme"
  puts "3. Press Cmd+U to run tests"

rescue StandardError => e
  puts "Error: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
end

main if __FILE__ == $PROGRAM_NAME
