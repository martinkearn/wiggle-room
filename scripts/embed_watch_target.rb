#!/usr/bin/env ruby
# Embeds the already-created, verified-working WiggleRoomWatch target into the
# iOS app bundle as a declared companion app, via the classic "Embed Watch
# Content" copy-files phase (dstSubfolderSpec 16, dstPath
# "$(CONTENTS_FOLDER_PATH)/Watch" — the same mechanism Xcode's own "Add
# Target > Watch App" wizard sets up, carried forward for single-target
# watchOS apps).

require 'xcodeproj'

project_path = File.expand_path('../src/WiggleRoom.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

main_target = project.targets.find { |t| t.name == 'WiggleRoom' }
watch_target = project.targets.find { |t| t.name == 'WiggleRoomWatch' }
raise 'targets not found' unless main_target && watch_target

main_target.add_dependency(watch_target)

embed_phase = main_target.new_copy_files_build_phase('Embed Watch Content')
embed_phase.dst_subfolder_spec = '16'
embed_phase.dst_path = '$(CONTENTS_FOLDER_PATH)/Watch'
build_file = embed_phase.add_file_reference(watch_target.product_reference)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

project.save
puts 'WiggleRoomWatch embedded into the WiggleRoom app bundle.'
