#!/usr/bin/env ruby
# Restores a real, shared .xcscheme for the main "Ringet" app target.
# Adding explicit shared schemes for RingetWidgets/RingetWatch last night
# silently disabled Xcode's scheme autocreation for the whole project
# (autocreation only runs when a project has *zero* explicit schemes) —
# so the "Ringet" scheme vanished from both xcodebuild and Xcode's own
# scheme picker. This recreates it properly, including the test target.

require 'xcodeproj'

project_path = File.expand_path('../src/Ringet.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

app_target = project.targets.find { |t| t.name == 'Ringet' }
tests_target = project.targets.find { |t| t.name == 'RingetTests' }
ui_tests_target = project.targets.find { |t| t.name == 'RingetUITests' }
raise 'targets not found' unless app_target && tests_target && ui_tests_target

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(app_target)
scheme.add_test_target(tests_target)
scheme.add_test_target(ui_tests_target)
scheme.set_launch_target(app_target)
scheme.save_as(project_path, 'Ringet', true)
puts 'Wrote shared scheme for Ringet.'
