module ApplicationHelper
  def markdown(str)
    sanitize(Commonmarker.to_html(str))
  end
end
