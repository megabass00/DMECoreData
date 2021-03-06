Pod::Spec.new do |s|
  s.name     = 'DMECoreData'
  s.version  = '1.0.0'
  s.license  = 'BSD'
  s.summary  = 'DMECoreData is a package of utilities about Core Data'
  s.homepage = 'https://github.com/damarte/DMECoreData'
  s.author   = { 'David Martínez' => 'damarte86@gmail.com' }
  s.source   = {
    :git => 'https://github.com/damarte/DMECoreData.git',
    :tag => '1.0.0'
  }
  s.requires_arc = true
  s.platform = :ios, '8.0'

  s.preserve_paths = 'README.md'
  s.ios.deployment_target = '8.0'

  s.framework = 'CoreData'
  s.dependency 'CocoaLumberjack'
  s.dependency 'AFNetworking', '> 2'
  s.dependency 'DMEThumbnailer'
  s.dependency 'Inflections'

  s.public_header_files = 'DMECoreData/*.h'

  s.source_files = 'DMECoreData/*.{h,m}'

  s.subspec 'Categories' do |ss|
    ss.source_files = 'DMECoreData/Categories/*.{h,m}'
  end

  s.subspec 'no-arc' do |sp|
    sp.source_files = 'DMECoreData/Categories/NSString+Inflections.{h,m}'
    sp.requires_arc = false
  end
end
