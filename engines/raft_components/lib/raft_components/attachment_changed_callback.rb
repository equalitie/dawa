#
# Will call a model's `attachment_changed(attachment)` method if any
# active storage attachment changes
#
module RaftComponents
  module AttachmentChangedCallback
    extend ActiveSupport::Concern

    prepended do
      after_commit :attachment_changed
    end

    def attachment_changed
      if self.record&.respond_to?(:attachment_changed)
        self.record.attachment_changed(self)
      end
    end
  end
end
