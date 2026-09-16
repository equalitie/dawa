#
# A concern that handles the behavior of user handles.
#
# This includes restrictions on usernames, validating usernames,
# finding users by username.
#
#
module Auth
  module UserUsername
    extend ActiveSupport::Concern

    # don't change this without also modifying the users.username column width:
    MAX_USERNAME_LENGTH = 40

    # require number or letter as first digit, don't allow two symbols in a row
    USERNAME_RE = /\A[a-z0-9]+([-_\.]?[a-z0-9])+\z/

    included do
      validates :username,
        presence: true,
        format: {with: USERNAME_RE},
        length: {in: 2..MAX_USERNAME_LENGTH}

      validate :validate_username
      before_create :downcase_username
    end

    # def username=(username)
    #   if new_record?
    #     write_attribute(:username, username)
    #   else
    #     raise ArgumentError, 'attempt to change username: use update_username!()'
    #   end
    # end

    # def update_username!(new_username)
    #   if self.username == new_username || !new_username.present?
    #     return true
    #   else
    #     User.transaction do
    #       write_attribute(:username, new_username)
    #       save!
    #     end
    #   end
    # end

    class_methods do
      #
      # Checks to see that the username is in a format
      # that we consider to be acceptable
      #
      def username_valid?(username)
        username_allowed?(username) &&
        username.length <= MAX_USERNAME_LENGTH &&
        username =~ USERNAME_RE
      end

      #
      # returns true if the username is not in the list of forbidden usernames, or
      # ASCII homographs of forbidden usernames.
      #
      def username_allowed?(username)
        if Auth.forbidden_usernames
          Auth.forbidden_regexps ||= begin
            Regexp.union(
              Auth.forbidden_usernames.map { |uname|
                Regexp.new(
                  "\\A" +
                    uname.
                    gsub(/[o0]/, '[o0]').
                    gsub(/[i1l]/, '[i1l]').
                    gsub(/e/, '[e3]').
                    gsub(/s/, '[s5]').
                    gsub(/b/, '[b8]').
                    gsub(/[_-]/, "([\\._-]|)").
                    gsub(/\*/, '.*') +
                  "[s0-9_-]*\\z"
                )
              }
            )
          end
          !Auth.forbidden_regexps.match(username)
        else
          true
        end
      end

      def username_taken?(username)
        return !!self.find_by(username: username)
      end
    end

    private

    def validate_username
      if username_changed?
        if self.class.username_taken?(self.username) && errors[:username].empty?
          errors.add 'username', I18n.t('errors.messages.taken')
        end
        if !self.class.username_allowed?(self.username) && errors[:username].empty?
          errors.add 'username', I18n.t('errors.messages.taken')
        end
      end
    end

    # before_create
    def downcase_username
      write_attribute(:username, self.username.downcase)
    end
  end
end
