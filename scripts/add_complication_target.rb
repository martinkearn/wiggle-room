#!/usr/bin/env ruby
# Adds the WiggleRoomComplication target — a WidgetKit extension embedded in
# the watch app, providing the watch face complication called for by §7.3 of
# the build spec (the companion app existed already; this is its missing
# complication). Mirrors add_widget_target.rb's approach almost exactly, just
# targeting watchOS and embedding into WiggleRoomWatch instead of WiggleRoom.

require 'xcodeproj'

project_path = File.expand_path('../src/WiggleRoom.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

watch_target = project.targets.find { |t| t.name == 'WiggleRoomWatch' }
shared_group = project.main_group.children.find { |g| g.respond_to?(:path) && g.path == 'WiggleRoomShared' }
raise 'WiggleRoomWatch target not found' unless watch_target
raise 'WiggleRoomShared group not found' unless shared_group

# --- Complication extension's own source group ---
complication_group = project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedRootGroup)
complication_group.path = 'WiggleRoomComplication'
complication_group.source_tree = '<group>'
project.main_group.children << complication_group

complication_exceptions = project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedBuildFileExceptionSet)
complication_exceptions.membership_exceptions = ['Info.plist', 'WiggleRoomComplication.entitlements']

# --- The extension target itself ---
complication_target = project.new_target(
  :app_extension,
  'WiggleRoomComplication',
  :watchos,
  '26.0',
  nil,
  :swift
)
complication_target.build_configuration_list.build_configurations.each do |config|
  config.build_settings.delete('INFOPLIST_FILE')
end

complication_exceptions.target = complication_target
complication_group.exceptions << complication_exceptions
complication_target.file_system_synchronized_groups << complication_group
complication_target.file_system_synchronized_groups << shared_group

common_settings = {
  'CODE_SIGN_ENTITLEMENTS' => 'WiggleRoomComplication/WiggleRoomComplication.entitlements',
  'CODE_SIGN_STYLE' => 'Automatic',
  'CURRENT_PROJECT_VERSION' => '1',
  'DEVELOPMENT_TEAM' => 'KP8NBNSB5M',
  'GENERATE_INFOPLIST_FILE' => 'YES',
  'INFOPLIST_FILE' => 'WiggleRoomComplication/Info.plist',
  'INFOPLIST_KEY_CFBundleDisplayName' => 'Wiggle Room Complication',
  'MARKETING_VERSION' => '1.0',
  'PRODUCT_BUNDLE_IDENTIFIER' => 'martinkearn.WiggleRoom.watchkitapp.WiggleRoomComplication',
  'PRODUCT_NAME' => '$(TARGET_NAME)',
  'SDKROOT' => 'watchos',
  'SKIP_INSTALL' => 'YES',
  'SUPPORTED_PLATFORMS' => 'watchsimulator watchos',
  'SWIFT_APPROACHABLE_CONCURRENCY' => 'YES',
  'SWIFT_DEFAULT_ACTOR_ISOLATION' => 'MainActor',
  'SWIFT_EMIT_LOC_STRINGS' => 'YES',
  'SWIFT_VERSION' => '5.0',
  'TARGETED_DEVICE_FAMILY' => '4',
  'WATCHOS_DEPLOYMENT_TARGET' => '26.0',
}

complication_target.build_configuration_list.build_configurations.each do |config|
  config.build_settings.merge!(common_settings)
  config.build_settings.delete('IPHONEOS_DEPLOYMENT_TARGET')
  config.build_settings.delete('MACOSX_DEPLOYMENT_TARGET')
  config.build_settings.delete('XROS_DEPLOYMENT_TARGET')
end

# --- Embed the extension into the watch app ---
watch_target.add_dependency(complication_target)

embed_phase = watch_target.new_copy_files_build_phase('Embed Foundation Extensions')
embed_phase.symbol_dst_subfolder_spec = :plug_ins
build_file = embed_phase.add_file_reference(complication_target.product_reference)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

project.save
puts 'WiggleRoomComplication target added and embedded into WiggleRoomWatch.'
