module Dawa
  module Demo
    def self.seed
      require "faker"
      if User.count == 0
        create_users
        create_people
      end
    end

    private

    def self.create_users
      User.create!(username: "demo-admin", display_name: "Demo Admin") do |user|
        user.is_active = true
        user.is_admin = true
        user.is_finalized = true
      end

      User.create!(username: "demo-user", display_name: "Demo User") do |user|
        user.is_active = true
        user.is_admin = false
        user.is_finalized = true
      end
    end

    def self.create_people
      40.times do
        first_name = Faker::Name.first_name
        display_name = [first_name, Faker::Name.last_name].join(" ")
        username = first_name.downcase + rand(100..999).to_s
        User.create!(username: username, display_name: display_name) do |user|
          user.email = "#{username}@example.com"
          user.is_active = rand(0..3) != 0
          user.is_admin = rand(0..3) != 0
          user.is_finalized = true
        end
      end
    end
  end
end
