Gem::Specification.new do |spec|
  spec.name        = "raft_components"
  spec.version     = "0.1.0"
  spec.authors     = [ "Raft Developers" ]
  spec.summary     = "A View Component collection"
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "Rakefile", "README.md"]
  end
  spec.add_dependency "view_component", "~> 4.12"
  spec.add_dependency "haml-rails"
  spec.add_dependency "bootstrap-icons-helper", "~> 2.0"
  spec.add_development_dependency "importmap-rails"
  spec.add_development_dependency "propshaft"
end
