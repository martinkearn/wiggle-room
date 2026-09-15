#!/usr/bin/env ruby
# Adds the WiggleRoomWatch companion app target. See add_widget_target.rb for
# why this is scripted rather than done via Xcode's wizard.

require 'xcodeproj'

project_path = File.expand_path('../src/WiggleRoom.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

main_target = project.targets.find { |t| t.name == 'WiggleRoom' }
shared_group = project.main_group.children.find { |g| g.respond_to?(:path) && g.path == 'WiggleRoomShared' }
raise 'WiggleRoom target not found' unless main_target
raise 'WiggleRoomShared group not found — run add_widget_target.rb first' unless shared_group

watch_group = project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedRootGroup)
watch_group.path = 'WiggleRoomWatch'
watch_group.source_tree = '<group>'
project.main_group.children << watch_group

watch_exceptions = project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedBuildFileExceptionSet)
watch_exceptions.membership_exceptions = ['Info.plist', 'WiggleRoomWatch.entitlements']

watch_target = project.new_target(
  :application,
  'WiggleRoomWatch',
  :watchos,
  '26.5',
  nil,
  :swift
)
watch_target.build_configuration_list.build_configurations.each do |config|
  config.build_settings.delete('INFOPLIST_FILE')
end

watch_exceptions.target = watch_target
watch_group.exceptions << watch_exceptions
watch_target.file_system_synchronized_groups << watch_group
watch_target.file_system_synchronized_groups << shared_group

common_settings = {
  'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME' => 'AccentColor',
  'CODE_SIGN_ENTITLEMENTS' => 'WiggleRoomWatch/WiggleRoomWatch.entitlements',
  'CODE_SIGN_STYLE' => 'Automatic',
  'CURRENT_PROJECT_VERSION' => '1',
  'DEVELOPMENT_TEAM' => 'KP8NBNSB5M',
  'ENABLE_PREVIEWS' => 'YES',
  'GENERATE_INFOPLIST_FILE' => 'YES',
  'INFOPLIST_FILE' => 'WiggleRoomWatch/Info.plist',
  'INFOPLIST_KEY_CFBundleDisplayName' => 'Wiggle Room',
  'INFOPLIST_KEY_UISupportedInterfaceOrientations' => 'UIInterfaceOrientationPortrait',
  'MARKETING_VERSION' => '1.0',
  'PRODUCT_BUNDLE_IDENTIFIER' => 'martinkearn.WiggleRoom.watchkitapp',
  'PRODUCT_NAME' => '$(TARGET_NAME)',
  'SDKROOT' => 'watchos',
  'SKIP_INSTALL' => 'YES',
  'SUPPORTED_PLATFORMS' => 'watchsimulator watchos',
  'SWIFT_APPROACHABLE_CONCURRENCY' => 'YES',
  'SWIFT_DEFAULT_ACTOR_ISOLATION' => 'MainActor',
  'SWIFT_EMIT_LOC_STRINGS' => 'YES',
  'SWIFT_VERSION' => '5.0',
  'TARGETED_DEVICE_FAMILY' => '4',
  'WATCHOS_DEPLOYMENT_TARGET' => '26.5',
}

watch_target.build_configuration_list.build_configurations.each do |config|
  config.build_settings.merge!(common_settings)
  config.build_settings.delete('IPHONEOS_DEPLOYMENT_TARGET')
  config.build_settings.delete('MACOSX_DEPLOYMENT_TARGET')
  config.build_settings.delete('XROS_DEPLOYMENT_TARGET')
end

project.save
puts 'Standalone WiggleRoomWatch target added (not yet embedded in the iOS app).'
