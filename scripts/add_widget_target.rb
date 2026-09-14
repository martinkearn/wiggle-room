#!/usr/bin/env ruby
# One-off script used to add the RingetWidgets extension target to the
# Xcode project via the `xcodeproj` gem, since this project uses the newer
# folder-synchronized group format (PBXFileSystemSynchronizedRootGroup) that
# Xcode's own "New Target" wizard would otherwise be needed for. Not part of
# the app; kept for reference/reproducibility, not run again once the target
# exists.

require 'xcodeproj'

project_path = File.expand_path('../src/Ringet.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

main_target = project.targets.find { |t| t.name == 'Ringet' }
raise 'Ringet target not found' unless main_target

# --- Shared code group, visible to both the app and the widget extension ---
shared_group = project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedRootGroup)
shared_group.path = 'RingetShared'
shared_group.source_tree = '<group>'
project.main_group.children << shared_group
main_target.file_system_synchronized_groups << shared_group

# --- Widget extension's own source group ---
widget_group = project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedRootGroup)
widget_group.path = 'RingetWidgets'
widget_group.source_tree = '<group>'
project.main_group.children << widget_group
# Info.plist and the entitlements file are referenced directly by build
# settings, not compiled as sources — exclude them from the synced group's
# membership the same way the main app's Info.plist is excluded.
widget_exceptions = project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedBuildFileExceptionSet)
widget_exceptions.membership_exceptions = ['Info.plist', 'RingetWidgets.entitlements']

# --- The extension target itself ---
widget_target = project.new_target(
  :app_extension,
  'RingetWidgets',
  :ios,
  '26.5',
  nil,
  :swift
)
widget_target.build_configuration_list.build_configurations.each do |config|
  config.build_settings.delete('INFOPLIST_FILE')
end

widget_exceptions.target = widget_target
widget_group.exceptions << widget_exceptions
widget_target.file_system_synchronized_groups << widget_group
widget_target.file_system_synchronized_groups << shared_group

# Remove the default Sources/Resources/Frameworks build phases' auto-added
# file references from new_target's scaffolding, if any — new_target for
# :app_extension creates empty build phases already, which is what we want
# since all sources come from the synchronized groups above.

common_settings = {
  'CODE_SIGN_ENTITLEMENTS' => 'RingetWidgets/RingetWidgets.entitlements',
  'CODE_SIGN_STYLE' => 'Automatic',
  'CURRENT_PROJECT_VERSION' => '1',
  'DEVELOPMENT_TEAM' => 'KP8NBNSB5M',
  'GENERATE_INFOPLIST_FILE' => 'YES',
  'INFOPLIST_FILE' => 'RingetWidgets/Info.plist',
  'INFOPLIST_KEY_CFBundleDisplayName' => 'Ringet Widgets',
  'IPHONEOS_DEPLOYMENT_TARGET' => '26.5',
  'MACOSX_DEPLOYMENT_TARGET' => '26.5',
  'MARKETING_VERSION' => '1.0',
  'PRODUCT_BUNDLE_IDENTIFIER' => 'martinkearn.Ringet.RingetWidgets',
  'PRODUCT_NAME' => '$(TARGET_NAME)',
  'SDKROOT' => 'auto',
  'SKIP_INSTALL' => 'YES',
  'SUPPORTED_PLATFORMS' => 'iphoneos iphonesimulator macosx',
  'SWIFT_APPROACHABLE_CONCURRENCY' => 'YES',
  'SWIFT_EMIT_LOC_STRINGS' => 'YES',
  'SWIFT_VERSION' => '5.0',
  'TARGETED_DEVICE_FAMILY' => '1,2,7',
}

widget_target.build_configuration_list.build_configurations.each do |config|
  config.build_settings.merge!(common_settings)
end

# --- Embed the extension into the main app ---
main_target.add_dependency(widget_target)

embed_phase = main_target.new_copy_files_build_phase('Embed Foundation Extensions')
embed_phase.symbol_dst_subfolder_spec = :plug_ins
build_file = embed_phase.add_file_reference(widget_target.product_reference)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

project.save
puts 'Widget extension target added.'
