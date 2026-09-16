module LayoutFlashHelper
  #
  # Generates HTML markup from flash messages.
  #
  # messages argument may be a String, Array, Exception, or ActiveModel::Errors
  #
  # Example:
  #
  # - flash.each do |name, messages|
  #   = content_tag :div, class: "alert alert-#{name}" do
  #     = flash_messages(messages)
  #
  def flash_messages(messages)
    if messages.nil? || (messages.respond_to?(:empty?) && messages.empty?)
      return nil
    end

    bullets = []
    messages = [ messages ].flatten

    messages.each do |msg|
      if msg.is_a?(String)
        bullets << safe_format(msg)
      elsif msg.respond_to?(:errors)
        msg.errors.full_messages.each do |i|
          bullets << safe_format(i)
        end
      elsif msg.respond_to?(:full_messages)
        msg.full_messages.each do |i|
          bullets << safe_format(i)
        end
      elsif msg.is_a?(ErrorMessage)
        msg.messages.each do |i|
          bullets << safe_format(i)
        end
      elsif msg.is_a?(StandardError)
        bullets << safe_format(msg.to_s)
      elsif msg.is_a?(Array) && msg.any?
        msg.each do |i|
          bullets << safe_format(i)
        end
      end
    end

    if bullets.size == 1
      bullets.first
    else
      content_tag(:ul) {
        bullets.map { |b| content_tag(:li, b) }.join("\n").html_safe
      }
    end
  end

  private

  ##
  ## FORMATTING FLASH
  ##

  SAFE_FORMAT_MAP = {
    "[b]"  => "<b>",
    "[/b]" => "</b>",
    "[r]"  => "<span style='color:red; font-weight: bold'>",
    "[/r]" => "</span>"
  }

  SAFE_FORMAT_RE = Regexp.union(SAFE_FORMAT_MAP.keys)

  def safe_format(str)
    h(str).gsub(SAFE_FORMAT_RE, SAFE_FORMAT_MAP).html_safe
  end
end
