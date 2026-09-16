class Auth::CredentialJob < ApplicationJob
  #
  # clean up credentials that never finished setup process
  #
  def perform()
    Auth::Credential.where(
      "updated_at < ? AND is_active = ?",
      24.hours.ago, false
    ).delete_all
  end
end
