#
# A very simple decorator system: call d(record) to access the decorator.
#
# Example:
#
# class Person < ApplicationRecord
# end
#
# class PersonDecorator
#   def full_name
#     "#{@person.first_name} #{@person.last_name}"
#   end
#   def icon
#     @view.render_icon(@person)
#   end
# end
#
# In a view:
#
#    <%= d(person).full_name %>
#    <%= d(person).icon %>
#
# Why do it this way?
#
# * automatic decorators often conflict with other gems
# * no need for a third party gem when this is so simple and works great
#
module DecoratorConcern
  extend ActiveSupport::Concern

  included do
    helper_method :d
  end

  def d(record, *args, **kwargs)
    if decorator = record.instance_variable_get("@decorator")
      decorator
    else
      decorator_name = resolve_name(record)
      decorator = "#{decorator_name.capitalize}Decorator".constantize.new(*args, **kwargs)
      decorator.instance_variable_set("@#{decorator_name.downcase}", record)
      decorator.instance_variable_set("@view", (self.respond_to?(:view_context) ? self.view_context : self))
      record.instance_variable_set("@decorator", decorator)
      decorator
    end
  end

  private

  def resolve_name(record)
    if record.respond_to?(:model_name)
      record.model_name.name # or model_name.element?
    elsif record.respond_to?(:decorator_name)
      record.decorator_name
    else
      record.class.name.demodulize
    end
  end

end
