#!/usr/bin/env ruby
# Adds a shared scheme for the new WiggleRoomComplication target — schemes
# don't autocreate once any explicit shared scheme exists in a project (see
# add_wiggleroom_scheme.rb), so every new target needs one added by hand.

require 'xcodeproj'

project_path = File.expand_path('../src/WiggleRoom.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'WiggleRoomComplication' }
raise 'WiggleRoomComplication target not found' unless target

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.set_launch_target(target)
scheme.save_as(project_path, 'WiggleRoomComplication', true)
puts 'Wrote shared scheme for WiggleRoomComplication.'
