require 'xcodeproj'
project_path = 'ios/StripeToddlerPOS/StripeToddlerPOS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

test_target = project.targets.find { |t| t.name == 'StripeToddlerPOSTests' }
tests_group = project.main_group.groups.find { |g| g.name == 'Tests' } || project.main_group.new_group('Tests')

file_reference = tests_group.new_reference('BackendAPIClientTests.swift')

if !test_target.source_build_phase.files.map { |f| f.file_ref.path }.include?('BackendAPIClientTests.swift')
  test_target.source_build_phase.add_file_reference(file_reference)
  puts 'Added BackendAPIClientTests.swift to StripeToddlerPOSTests target.'
else
  puts 'BackendAPIClientTests.swift is already in the StripeToddlerPOSTests target.'
end

project.save
