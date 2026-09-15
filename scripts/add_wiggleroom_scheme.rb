#!/usr/bin/env ruby
# Restores a real, shared .xcscheme for the main "WiggleRoom" app target.
# Adding explicit shared schemes for WiggleRoomWidgets/WiggleRoomWatch last night
# silently disabled Xcode's scheme autocreation for the whole project
# (autocreation only runs when a project has *zero* explicit schemes) —
# so the "WiggleRoom" scheme vanished from both xcodebuild and Xcode's own
# scheme picker. This recreates it properly, including the test target.

require 'xcodeproj'

project_path = File.expand_path('../src/WiggleRoom.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

app_target = project.targets.find { |t| t.name == 'WiggleRoom' }
tests_target = project.targets.find { |t| t.name == 'WiggleRoomTests' }
ui_tests_target = project.targets.find { |t| t.name == 'WiggleRoomUITests' }
raise 'targets not found' unless app_target && tests_target && ui_tests_target

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app_target)
scheme.add_test_target(tests_target)
scheme.add_test_target(ui_tests_target)
scheme.set_launch_target(app_target)
scheme.save_as(project_path, 'WiggleRoom', true)
puts 'Wrote shared scheme for WiggleRoom.'
