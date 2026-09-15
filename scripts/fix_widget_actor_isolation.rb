#!/usr/bin/env ruby
require 'xcodeproj'

project_path = File.expand_path('../src/WiggleRoom.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

widget_target = project.targets.find { |t| t.name == 'WiggleRoomWidgets' }
raise 'WiggleRoomWidgets target not found' unless widget_target

widget_target.build_configuration_list.build_configurations.each do |config|
  config.build_settings['SWIFT_DEFAULT_ACTOR_ISOLATION'] = 'MainActor'
end

project.save
puts 'Set SWIFT_DEFAULT_ACTOR_ISOLATION on WiggleRoomWidgets.'
