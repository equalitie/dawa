module DecoratorHelper
  def d(record, decorator_class = nil, *args, **kwargs)
    if decorator = record.instance_variable_get("@decorator")
      decorator
    else
      decorator_name = decorator_class || resolve_name(record)
      decorator = "#{decorator_name.capitalize}Decorator".constantize.new(*args, **kwargs)
      decorator.instance_variable_set("@#{decorator_name.downcase}", record)
      decorator.instance_variable_set("@view", self)
      record.instance_variable_set("@decorator", decorator)
      decorator
    end
  end

  private

  def resolve_name(record)
    if record.respond_to?(:model_name)
      record.model_name.name
    elsif record.respond_to?(:decorator_name)
      record.decorator_name
    else
      record.class.name.demodulize
    end
  end
end
