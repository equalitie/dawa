require_relative "../test_helper"

class SessionVaultTest < ActiveSupport::TestCase
  def setup
    @vault = Auth::SessionVault.new
  end

  def test_set_replaces_entire_vault
    @vault.set({ "key1" => "value1" })
    assert_equal "value1", @vault.to_h["key1"]

    @vault.set({ "key2" => "value2" })
    assert_nil @vault.to_h["key1"]
    assert_equal "value2", @vault.to_h["key2"]
  end

  def test_set_converts_binary_to_hex
    binary_val = SecureRandom.random_bytes(16)
    @vault.set({ "secret" => binary_val })
    stored = @vault.to_h["secret"]
    # stored should be hex string, not binary
    assert_equal binary_val.unpack("H*").first, stored
  end

  def test_set_with_nil_empties_vault
    @vault.set({ "key1" => "value1" })
    @vault.set(nil)
    assert_equal({}, @vault.to_h)
  end

  def test_merge_adds_to_existing_vault
    @vault.set({ "key1" => "value1" })
    @vault.merge({ "key2" => "value2" })
    assert_equal "value1", @vault.to_h["key1"]
    assert_equal "value2", @vault.to_h["key2"]
  end

  def test_merge_overwrites_duplicate_keys
    @vault.set({ "key1" => "old" })
    @vault.merge({ "key1" => "new" })
    assert_equal "new", @vault.to_h["key1"]
  end

  def test_exists_returns_true_when_vault_has_entries
    assert_not @vault.exists?
    @vault.set({ "key" => "value" })
    assert @vault.exists?
  end

  def test_to_h_returns_vault_hash
    assert_equal({}, @vault.to_h)
    @vault.set({ "a" => "b" })
    assert_equal({ "a" => "b" }, @vault.to_h)
  end

  def test_get_raises_argument_error_for_nil
    assert_raises(ArgumentError) { @vault.get(nil) }
  end

  def test_get_raises_standard_error_when_key_missing
    assert_raises(StandardError) { @vault.get(1) }
  end

  def test_get_returns_binary_for_hex_stored_value
    @vault.set({ "workspace/1" => "deadbeef" })
    result = @vault.get(1)
    assert_equal Encoding::BINARY, result.encoding
    assert_equal ["deadbeef"].pack("H*"), result
  end

  def test_get_with_integer_constructs_workspace_key
    @vault.set({ "workspace/5" => "ca fe ba be".delete(" ") })
    result = @vault.get(5)
    assert result
  end

  def test_put_adds_key_to_vault
    binary_val = SecureRandom.random_bytes(16)
    @vault.put(1, binary_val)
    assert @vault.has?(1)
  end

  def test_put_converts_binary_to_hex
    binary_val = SecureRandom.random_bytes(16)
    @vault.put(1, binary_val)
    hex_val = binary_val.unpack("H*").first
    assert_equal hex_val, @vault.to_h["workspace/1"]
  end

  def test_has_key_returns_true_when_key_exists
    @vault.put(1, "secret")
    assert @vault.has?(1)
  end

  def test_has_key_returns_false_when_key_missing
    assert_not @vault.has?(99)
  end

  def test_has_raises_argument_error_for_nil
    assert_raises(ArgumentError) { @vault.has?(nil) }
  end

  def test_create_new_key_generates_and_stores_random_key
    @vault.create_new_key(1)
    assert @vault.has?(1)
    stored = @vault.get(1)
    assert_equal Encoding::BINARY, stored.encoding
    assert_equal 64, stored.bytesize
  end

  def test_initialize_with_session_hash
    vault = Auth::SessionVault.new({ vault: { "a" => "b" } })
    assert_equal "b", vault.to_h["a"]
  end
end
