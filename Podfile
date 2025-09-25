# Uncomment the next line to define a global platform for your project
platform :osx, '12.0'

target 'MacScreenCapture' do
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!

  # Pods for MacScreenCapture
  # 如果需要第三方库，可以在这里添加
  # pod 'Alamofire', '~> 5.6'
  # pod 'SwiftyJSON', '~> 5.0'

  target 'MacScreenCaptureTests' do
    inherit! :search_paths
    # Pods for testing
  end

  target 'MacScreenCaptureUITests' do
    # Pods for testing
  end
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '12.0'
    end
  end
end