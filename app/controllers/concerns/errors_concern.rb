
module ErrorsConcern
  extend ActiveSupport::Concern

  class ErrorMessage < Exception
    attr_reader :color
    def initialize(msg, color)
      @color = color
      super(msg)
    end
  end

  def error_message!(msg, color = :danger)
    raise ErrorMessage.new(msg, color)
  end

  included do
    # to see error pages in development mode, set consider_all_requests_local
    # to `false` in config/environments/development.rb

    rescue_from ErrorMessage,                    with: :render_message

    unless Rails.application.config.consider_all_requests_local
      rescue_from StandardError,                   with: :render_exception
      rescue_from "NotFound",                      with: :render_not_found
      rescue_from ActiveRecord::RecordNotFound,    with: :render_not_found
      rescue_from ActionController::RoutingError,  with: :render_not_found
      rescue_from ActiveRecord::ConnectionNotEstablished, with: :render_exception
    end

    helper_method :error_message!
  end


  protected

  def render_exception(exc)
    notify_exception(exc)
    render template: "errors/exception", status: 500, layout: "inset"
  end

  def render_not_found
    respond_to do |format|
      format.html { render template: "errors/not_found", layout: "inset", status: 404 }
      format.all  { head 404 }
    end
  end

  def notify_exception(exc, msg: nil)
    log_exception(exc)
    if defined?(ExceptionNotifier)
      ExceptionNotifier.notify_exception(
        exc, env: request.env, data: { message: msg, user: current_user&.login }
      )
    end
  end

  def log_exception(exc)
    logger.error("EXCEPTION (%s): %s -- %s" % [exc.class, exc.to_s, exc.backtrace[0..10].join(" >>> ")])
  end

  def log_error(msg)
    logger.error("ERROR: %s -- %s" % [msg, caller[1..11].join(" >>> ")])
  end

  def render_message(exception)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.append("alerts", helpers.v.alert(exception.color) { helpers.content_tag(:p, exception.to_s) })
      end
      format.html do
        @message = exception.to_s
        @color = exception.color
        render template: "errors/message"
      end
    end
  end
end
