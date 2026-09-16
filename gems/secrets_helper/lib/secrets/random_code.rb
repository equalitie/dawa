require 'securerandom'

#
#
# Generates a random code in which there are no ambiguous characters.
# This way, no one has to puzzle if that is an 'l' or a '1'.
#
# With only lowercase and no ambiguous characters, the entropy of strings
# generated with RandomCode is lower than a string with capital letters
# and confusing characters. To compensate, you should pick a longer string.
#
# Entropy is:
#
#   possible_chars = 32
#   Math.log(possible_chars**length, 2)
#
# length 8  => 96 bits
# length 9  => 101 bits
# length 10 => 106 bits
# length 11 => 110 bits
# length 12 => 114 bits
# length 13 => 118 bits
# length 14 => 121 bits
# length 15 => 125 bits
# length 16 => 128 bits
# length 17 => 130 bits
# length 18 => 133 bits
# length 19 => 135 bits
# length 20 => 138 bits
#
module Secrets
  module RandomCode
    POSSIBLE_10 = %w[0 1 2 3 4 5 6 7 8 9]
    POSSIBLE_32 = %w[a b c d e f g h i j k m n p q r s t u v w x y z 2 3 4 5 6 7 8 9]
    POSSIBLE_56 = %w[A B C D E F G H J K L M N P Q R S T U V W Y X Z a b c d e f g h i j k m n p q r s t u v w x y z 2 3 4 5 6 7 8 9]

    def self.entropy(length)
      Math.log(POSSIBLE_32.length**length, 2).truncate
    end

    #
    # creates a random string of only unambiguous characters.
    # if split is specified, adds a '-' characters every split chars.
    #
    def self.create(length, split=nil)
      generate_random_string(length, split, POSSIBLE_32)
    end

    #
    # same as create(), but includes uppercase and lowercase letters
    # for added entropy.
    #
    def self.create_mixcase(length, split=nil)
      generate_random_string(length, split, POSSIBLE_56)
    end

    #
    # only use numbers
    #
    def self.create_numeric(length, split=nil)
      generate_random_string(length, split, POSSIBLE_10)
    end

    # returns true if str could have been a random code
    def self.match?(str, length)
      0 == (str =~ /\A[#{POSSIBLE_32.join(',')}]{#{length.to_i}}\z/)
    end

    # returns true if str could have been a mixed case random code
    def self.match_mixcase?(str, length)
      0 == (str =~ /\A[#{POSSIBLE_56.join(',')}]{#{length.to_i}}\z/)
    end

    protected

    def self.generate_random_string(length, split, possible_chars)
      possible = possible_chars.shuffle
      str = SecureRandom.random_bytes(length).each_byte.map {|byte|
        possible[byte % possible.length]
      }.join
      if split
        return str.scan(/.{#{split}}/).join('-')
      else
        return str
      end
    end

  end
end
