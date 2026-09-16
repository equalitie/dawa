#
# Usage:
#
# class Book < ActiveRecord::Base
#   has_code length: 10, type: "mixed"
# end
#
# options:
# * length: the number of chars
# * type: one of "numeric", "mixed", "lower", "upper"
#
# The default is length = 6, type = upper
#
module Secrets
  module HasCode
    module DefineHasCodeMethod
      def has_code(configuration={})
        before_validation :generate_code, on: :create
        class_attribute :has_code_config
        self.has_code_config = {length: 6, type: "upper"}.merge(configuration)
        extend(HasCode::ClassMethods)
        include(HasCode::InstanceMethods)
      end
    end

    module ClassMethods
      def find_by_encrypted_code(code)
        if !code.present?
          return nil
        else
          code = SecretUrl::decrypt(code.strip)&.split('|')&.first
          return find_by_code(code)
        end
      end

      def find_by_any_code(code)
        if !code.present?
          return nil
        elsif code =~ /^[A-Z0-9]{#{self.has_code_config[:length]}}$/i
          return find_by_code(code.upcase)
        else
          return find_by_encrypted_code(code)
        end
      end

      def is_a_code?(code)
        code =~ /\A[A-Z0-9]{#{self.has_code_config[:length]}}\z/
      end
    end

    module InstanceMethods

      def to_encrypted_param
        SecretUrl::encrypt(code)
      end

      def generate_code
        type = self.class.has_code_config[:type].to_s
        length = self.class.has_code_config[:length].to_i
        begin
          self.code = if type == "numeric"
            RandomCode.create_numeric(length)
          elsif type == "upper"
            RandomCode.create(length).upcase
          elsif type == "lower"
            RandomCode.create(length)
          elsif type == "mixed"
            RandomCode.create_mixcase(length)
          end
        end until self.class.find_by_code(self.code).nil?
      end
    end
  end
end
