# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

return unless Rails.env.local?

require "faker"

User.destroy_all

User.create!(username: "demo", display_name: "Demo Admin") do |user|
  user.is_active = true
  user.is_admin = true
end

20.times do
  first_name = Faker::Name.first_name
  display_name = [first_name, Faker::Name.last_name].join(" ")
  username = first_name.downcase + rand(100..999).to_s
  User.create!(username: username, display_name: display_name) do |user|
    user.email = "#{username}@example.com"
    user.is_active = rand(0..3) != 0
    user.is_admin = rand(0..3) != 0
  end
end
