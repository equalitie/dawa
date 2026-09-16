require_relative "test_helper"

class RandomCodeTest < Minitest::Test

  class Thing < ActiveRecord::Base
    extend Secrets::HasCode::DefineHasCodeMethod
    has_code length: 10, type: "upper"
  end

  def setup
    ActiveRecord::Base.connection.create_table :things do |t|
      t.column :code, :string
    end
  end

  def teardown
    drop_tables
  end

  def test_creation
    record = Thing.create
    assert record.code.present?
    assert_equal 10, record.code.length, record.code
  end

end
