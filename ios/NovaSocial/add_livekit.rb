#!/usr/bin/env ruby

require 'xcodeproj'

project_path = 'ICERED.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Add LiveKit package
livekit_package = project.root_object.package_references.find do |ref|
  ref.repositoryURL == 'https://github.com/livekit/client-sdk-swift.git'
end

unless livekit_package
  puts "📦 Adding LiveKit SDK package reference..."

  livekit_package = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  livekit_package.repositoryURL = 'https://github.com/livekit/client-sdk-swift.git'
  livekit_package.requirement = {
    'kind' => 'upToNextMajorVersion',
    'minimumVersion' => '2.0.0'
  }

  project.root_object.package_references << livekit_package

  # Add to ICERED target
  target = project.targets.find { |t| t.name == 'ICERED' }

  if target
    puts "🎯 Adding LiveKit to ICERED target..."

    product_dependency = target.package_product_dependencies.find do |dep|
      dep.product_name == 'LiveKit'
    end

    unless product_dependency
      product_dependency = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
      product_dependency.product_name = 'LiveKit'
      product_dependency.package = livekit_package

      target.package_product_dependencies << product_dependency
    end
  end

  project.save
  puts "✅ LiveKit SDK has been added successfully!"
  puts ""
  puts "Next steps:"
  puts "1. Open Xcode and let it resolve the package"
  puts "2. Build the project"
else
  puts "ℹ️  LiveKit SDK is already added to the project"
end
