require_relative "test_helper"

class Secrets::TinyUrlTest < Minitest::Test

  def test_roundtrip
    1000.times do
      number = rand(1_000_000_000)
      assert_equal number, Secrets::TinyUrl.decode(Secrets::TinyUrl.encode(number))
    end
  end

  def test_encoding
    tests = {
      0 => "",
      1 => "AQ",
      100 => "Z",
      1002 => "6gM",
      2**16 => "AAAB",
      1_000_000 => "QEIP",
      2**24-1 => "____",
      2**64-1 => "__________8"
    }
    tests.each do |number, expected_encoding|
      encoded_str = Secrets::TinyUrl.encode(number)
      unless number == 0
        assert Secrets::TinyUrl.match?(encoded_str), "#{encoded_str} should match"
        assert !Secrets::TinyUrl.match?(encoded_str+"+")
      end
      assert_equal expected_encoding, encoded_str
    end
  end

  def test_with_wrong_secret
    assert_raises ArgumentError do
      Secrets::TinyUrl.encode(100, 'name_does_not_exist')
    end
  end

  def test_with_secret
    tests = [
      ['secret_1', 100, 'g0vQ'],
      ['secret_1', 100, 'g0vQ'],
      ['secret_2', 100, 'g0qg'],
      ['secret_2', 1000000000, 'HQFMs89Q']
    ]
    tests.each do |test|
      ENV['MY_SECRET'] = test[0]
      expected_encoding = test[2]
      input_number = test[1]

      encoded_str = Secrets::TinyUrl.encode(input_number, 'my_secret')
      assert_equal expected_encoding, encoded_str, "should encode correctly"

      decoded_number = Secrets::TinyUrl.decode(encoded_str, 'my_secret')
      assert_equal input_number, decoded_number, "should decode correctly"

      assert input_number != Secrets::TinyUrl.decode(encoded_str), "should not decode without secret"

      assert Secrets::TinyUrl.match?(encoded_str), "encoding should be recognized"
    end
  end

  def test_checksum
    # all arbitrary strings of the right characters and length will decode
    assert Secrets::TinyUrl.decode("0219ga").is_a?(Integer)
    assert Secrets::TinyUrl.decode("jh29xP").is_a?(Integer)
    assert Secrets::TinyUrl.decode("92hg9").is_a?(Integer)
    assert Secrets::TinyUrl.decode("bNabvg15").is_a?(Integer)

    # but not if there is a secret set
    ENV['MY_SECRET'] = "hello"
    assert Secrets::TinyUrl.decode("0219ga", :my_secret).nil?
    assert Secrets::TinyUrl.decode("jh29xP", :my_secret).nil?
    assert Secrets::TinyUrl.decode("92hg9", :my_secret).nil?
    assert Secrets::TinyUrl.decode("bNabvg15", :my_secret).nil?
  end
end
