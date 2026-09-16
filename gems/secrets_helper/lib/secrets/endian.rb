module Secrets
  class Endian
    # Pack templates:
    # Big-endian: S> (16-bit), L> (32-bit), Q> (64-bit), n (16-bit), N (32-bit)
    # Little-endian: S< (16-bit), L< (32-bit), Q< (64-bit), v (16-bit), V (32-bit)

    def self.big_to_little_16(num)
      [num].pack('n').unpack('v').first
    end

    def self.little_to_big_16(num)
      [num].pack('v').unpack('n').first
    end

    def self.big_to_little_32(num)
      [num].pack('N').unpack('V').first
    end

    def self.little_to_big_32(num)
      [num].pack('V').unpack('N').first
    end

    def self.big_to_little_64(num)
      [num].pack('Q>').unpack('Q<').first
    end

    def self.little_to_big_64(num)
      [num].pack('Q<').unpack('Q>').first
    end

    # Auto-detect size conversion
    def self.big_to_little(num)
      if num <= 0xFFFF
        big_to_little_16(num)
      elsif num <= 0xFFFFFFFF
        big_to_little_32(num)
      else
        big_to_little_64(num)
      end
    end

    def self.little_to_big(num)
      if num <= 0xFFFF
        little_to_big_16(num)
      elsif num <= 0xFFFFFFFF
        little_to_big_32(num)
      else
        little_to_big_64(num)
      end
    end
  end
end
