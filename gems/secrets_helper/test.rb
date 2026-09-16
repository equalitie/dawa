require 'base64'

class BinaryEncoder
  # Encodes an unsigned integer and binary data to URL-safe base64
  # @param integer [Integer] Unsigned integer to encode
  # @param data [String] Binary data blob to encode
  # @return [String] URL-safe base64 encoded string
  def self.encode(integer, data = "")
    # Validate inputs
    raise ArgumentError, "Integer must be non-negative" if integer < 0
    raise ArgumentError, "Data must be a string" unless data.is_a?(String)
    
    # Convert integer to binary (big-endian, variable length)
    integer_bytes = integer_to_bytes(integer)
    
    # Combine integer length, integer bytes, and data
    # Format: [1 byte length] [integer bytes] [data bytes]
    combined = integer_bytes.bytesize.chr + integer_bytes + data
    
    # URL-safe base64 encoding (no padding)
    Base64.urlsafe_encode64(combined, padding: false)
  end

  # Decodes a URL-safe base64 string back to integer and binary data
  # @param encoded_str [String] URL-safe base64 encoded string
  # @return [Array(Integer, String)] Decoded integer and binary data
  def self.decode(encoded_str)
    raise ArgumentError, "Encoded string cannot be nil" if encoded_str.nil?
    
    # URL-safe base64 decoding
    decoded = Base64.urlsafe_decode64(encoded_str)
    
    # Extract integer length (first byte)
    integer_length = decoded.bytes[0]
    
    # Validate we have enough data
    if decoded.bytesize < 1 + integer_length
      raise ArgumentError, "Invalid encoded string: insufficient data"
    end
    
    # Extract integer bytes
    integer_bytes = decoded.byteslice(1, integer_length)
    
    # Extract remaining data
    data = decoded.byteslice(1 + integer_length..-1) || ""
    
    # Convert bytes back to integer
    integer = bytes_to_integer(integer_bytes)
    
    [integer, data]
  rescue ArgumentError => e
    # Re-raise our own ArgumentErrors
    raise e
  rescue => e
    raise ArgumentError, "Invalid base64 encoded string: #{e.message}"
  end

  # Helper method to encode just an integer
  # @param integer [Integer] Unsigned integer to encode
  # @return [String] URL-safe base64 encoded integer
  def self.encode_integer(integer)
    encode(integer, "")
  end

  # Helper method to encode just binary data
  # @param data [String] Binary data to encode
  # @return [String] URL-safe base64 encoded data
  def self.encode_data(data)
    encode(0, data)
  end

  private

  # Convert integer to variable-length byte string
  # @param integer [Integer] Unsigned integer
  # @return [String] Byte representation
  def self.integer_to_bytes(integer)
    return "\x00" if integer == 0
    
    bytes = []
    while integer > 0
      bytes.unshift(integer & 0xFF)
      integer >>= 8
    end
    bytes.pack('C*')
  end

  # Convert byte string back to integer
  # @param bytes [String] Byte representation
  # @return [Integer] Unsigned integer
  def self.bytes_to_integer(bytes)
    return 0 if bytes.nil? || bytes.empty?
    
    integer = 0
    bytes.each_byte do |byte|
      integer = (integer << 8) | byte
    end
    integer
  end
end

# Example usage and comprehensive tests
if __FILE__ == $0
  puts "BinaryEncoder Test Suite"
  puts "=" * 50

  # Test 1: Basic integer encoding
  puts "\n1. Basic Integer Encoding:"
  test_int = 42
  encoded = BinaryEncoder.encode_integer(test_int)
  decoded_int, decoded_data = BinaryEncoder.decode(encoded)
  
  puts "Original: #{test_int}"
  puts "Encoded: #{encoded}"
  puts "Decoded: #{decoded_int}"
  puts "Match: #{test_int == decoded_int ? '✓' : '✗'}"
  puts "Data empty: #{decoded_data.empty? ? '✓' : '✗'}"

  # Test 2: Integer with binary data
  puts "\n2. Integer with Binary Data:"
  test_int = 12345
  test_data = "Hello, World!\x00\x01\x02"  # Includes binary data
  encoded = BinaryEncoder.encode(test_int, test_data)
  decoded_int, decoded_data = BinaryEncoder.decode(encoded)
  
  puts "Original: #{test_int} + #{test_data.inspect}"
  puts "Encoded: #{encoded}"
  puts "Decoded: #{decoded_int} + #{decoded_data.inspect}"
  puts "Integer match: #{test_int == decoded_int ? '✓' : '✗'}"
  puts "Data match: #{test_data == decoded_data ? '✓' : '✗'}"

  # Test 3: Large integer
  puts "\n3. Large Integer:"
  large_int = 2**64 - 1  # Maximum 64-bit unsigned integer
  encoded = BinaryEncoder.encode_integer(large_int)
  decoded_int, _ = BinaryEncoder.decode(encoded)
  
  puts "Original: #{large_int}"
  puts "Encoded length: #{encoded.length}"
  puts "Decoded: #{decoded_int}"
  puts "Match: #{large_int == decoded_int ? '✓' : '✗'}"

  # Test 4: Zero and empty data
  puts "\n4. Zero and Empty Data:"
  encoded = BinaryEncoder.encode(0, "")
  decoded_int, decoded_data = BinaryEncoder.decode(encoded)
  
  puts "Encoded: #{encoded}"
  puts "Decoded: #{decoded_int} + #{decoded_data.inspect}"
  puts "Both zero/empty: #{decoded_int == 0 && decoded_data.empty? ? '✓' : '✗'}"

  # Test 5: Binary data only
  puts "\n5. Binary Data Only:"
  binary_data = "\x00\x01\x02\x03\xFF\xFE\xFD".b  # Explicit binary string
  encoded = BinaryEncoder.encode_data(binary_data)
  decoded_int, decoded_data = BinaryEncoder.decode(encoded)
  
  puts "Original data: #{binary_data.inspect}"
  puts "Encoded: #{encoded}"
  puts "Decoded: #{decoded_int} + #{decoded_data.inspect}"
  puts "Integer zero: #{decoded_int == 0 ? '✓' : '✗'}"
  puts "Data match: #{binary_data == decoded_data ? '✓' : '✗'}"

  # Test 6: Error handling
  puts "\n6. Error Handling:"
  begin
    BinaryEncoder.encode(-1)  # Negative integer
    puts "✗ Should have raised error for negative integer"
  rescue ArgumentError => e
    puts "✓ Correctly caught error: #{e.message}"
  end

  begin
    BinaryEncoder.decode("invalid_base64!!")  # Invalid base64
    puts "✗ Should have raised error for invalid base64"
  rescue ArgumentError => e
    puts "✓ Correctly caught error: #{e.message}"
  end

  # Test 7: URL safety verification
  puts "\n7. URL Safety Check:"
  test_int = 255
  test_data = "test/data"
  encoded = BinaryEncoder.encode(test_int, test_data)
  
  puts "Encoded: #{encoded}"
  puts "URL-safe chars only: #{encoded !~ /[+\/=]/ ? '✓' : '✗'}"
  puts "No padding: #{encoded !~ /=+$/ ? '✓' : '✗'}"
end

