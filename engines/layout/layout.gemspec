Gem::Specification.new do |spec|
  spec.name        = "layout"
  spec.version     = "0.1.0"
  spec.authors     = [ "Authors" ]
  spec.summary     = "Rails Layout Helper"

  spec.metadata["allowed_push_host"] = ""
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "README.md"]
  end

  spec.add_dependency "bootstrap"
end
