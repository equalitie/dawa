require "minitest/autorun"
require "active_record"
require_relative "../lib/secrets_helper"

database_adaptor       = ENV['CI_DB_TYPE'] || 'sqlite'
database_configuration = ENV['CI_DB_CONFIG'] || File.expand_path("../database.yml", __FILE__)

ActiveRecord::Base.configurations = YAML.safe_load(IO.read(database_configuration))
ActiveRecord::Base.establish_connection(database_adaptor.to_sym)
ActiveRecord::Schema.verbose = false

def drop_tables
  tables = ActiveRecord::Base.connection.data_sources
  tables.each do |table|
    ActiveRecord::Base.connection.drop_table(table)
  end
end
