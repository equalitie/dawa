module Auth
  class Attempt < ApplicationRecord
    self.table_name = "user_attempts"
    belongs_to :user
    belongs_to :credential, optional: true

    #
    # Attempts have two data hashes, one is used
    # for successful attempts (encrypted_data) and one
    # is used for unsuccessful attempts (cleartext_data)
    #
    # raft_encrypts :encrypted_data

    def data
      is_success? ? encrypted_data : cleartext_data
    end
  end
end
