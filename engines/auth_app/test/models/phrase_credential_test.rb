require_relative "../test_helper"

class PhraseCredentialTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(username: "user")
    @credential = Auth::Credential::Phrase.create!(user: @user)
    @secret = "My secret password"
  end

  def test_create_vault
    @credential.init_vault(@secret)

    assert_equal({}, @credential.read_vault(@secret))
    assert_raises ArgumentError do
      @credential.read_vault("wrong secret")
    end

    @credential.update_vault({"hello" => "world"})
    assert_equal({"hello" => "world"}, @credential.read_vault(@secret))
    assert_raises ArgumentError do
      @credential.read_vault("wrong secret")
    end
  end
end
