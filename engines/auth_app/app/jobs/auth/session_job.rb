class Auth::SessionJob < ApplicationJob
  def perform()
    Auth::Session.where(
      "updated_at < ? OR created_at < ?",
      words_to_time(Auth.user_session_idle_timeout),
      words_to_time(Auth.user_session_max_lifetime)
    ).delete_all
  end

  def words_to_time(str)
    raise ArgumentError unless str =~ /\A[0-9]+ (seconds?|minutes?|hours?|days?|weeks?|months?|years?)\z/
    Time.now.utc - str.split.inject { |count, unit| count.to_i.send(unit) }
  end
end
