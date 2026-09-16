namespace :secrets_helper do
  desc "Generate a secret compatible with SecretHelper"
  task :create do
    puts RbNaCl::Random.random_bytes(RbNaCl::SecretBox.key_bytes).unpack('H*')
  end
end
