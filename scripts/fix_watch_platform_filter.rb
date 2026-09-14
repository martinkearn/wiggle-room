#!/usr/bin/env ruby
# The watch app embed (dependency + copy-files build file) must not apply
# when the Ringet app target is built for macOS — a macOS app can't embed a
# watchOS binary. Scope both to iOS only via Xcode's platform filter.

require 'xcodeproj'

project_path = File.expand_path('../src/Ringet.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

main_target = project.targets.find { |t| t.name == 'Ringet' }
watch_target = project.targets.find { |t| t.name == 'RingetWatch' }
raise 'targets not found' unless main_target && watch_target

dependency = main_target.dependencies.find { |d| d.target == watch_target }
raise 'watch dependency not found' unless dependency
dependency.platform_filters = ['ios']

embed_phase = main_target.build_phases.find { |p| p.respond_to?(:name) && p.name == 'Embed Watch Content' }
raise 'embed phase not found' unless embed_phase
build_file = embed_phase.files.find { |f| f.file_ref == watch_target.product_reference }
raise 'watch build file not found' unless build_file
build_file.platform_filters = ['ios']

project.save
puts 'Scoped RingetWatch embedding to iOS only.'
