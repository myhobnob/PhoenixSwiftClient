# Uncomment the next line to define a global platform for your project
# platform :ios, '9.0'

workspace 'PhoenixSwiftClient.xcworkspace'

target 'PhoenixSwiftClient' do
  # Comment the next line if you're not using Swift and don't want to use dynamic frameworks
  use_frameworks!
  pod 'Starscream'

  # Pods for PhoenixSwiftClient

  target 'PhoenixSwiftClientTests' do
    inherit! :search_paths
    # Pods for testing
  end

end

target 'PhoenixSwiftClientExample' do
  project 'PhoenixSwiftClientExample/PhoenixSwiftClientExample.xcodeproj'
  use_frameworks!
  pod 'Starscream'
end
