#!/usr/bin/env ruby
# Persists real, shared .xcscheme files for the new targets. Without this,
# xcodebuild's on-the-fly scheme autocreation doesn't reliably carry
# platform/destination info for a watchOS target when the project has never
# been opened in Xcode.app itself.

require 'xcodeproj'

project_path = File.expand_path('../src/Ringet.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

%w[RingetWidgets RingetWatch].each do |name|
  target = project.targets.find { |t| t.name == name }
  raise "#{name} target not found" unless target

  scheme = Xcodeproj::XCScheme.new
  scheme.add_build_target(target)
  scheme.set_launch_target(target)
  scheme.save_as(project_path, name, true)
  puts "Wrote shared scheme for #{name}."
end
