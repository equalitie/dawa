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
      # constant time code finding
      # a little inefficient because we load all the ids for all the records.
      # if this gets too slow, we can add two columns, one for the code
      # and one for the code digest, then only search the digest
      def find_by_code(code)
        matching_id = all.pluck(:id, :code).find { |id, stored_code|
          ActiveSupport::SecurityUtils.secure_compare(stored_code, code)
        }&.first
        find_by(id: matching_id) if matching_id
      end

      def is_a_code?(code)
        code =~ /\A[A-Z0-9]{#{self.has_code_config[:length]}}\z/
      end
    end

    module InstanceMethods
      def to_param
        self.code
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
