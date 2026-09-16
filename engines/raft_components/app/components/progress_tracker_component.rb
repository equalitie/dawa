class ProgressTrackerComponent < ApplicationComponent
  renders_many :steps, ProgressStepComponent

  haml_template <<-HAML
- if @mode == 'progress'
  .progress-steps.d-flex.align-items-center
    .flex-grow-1
    - completed = true
    - steps.each do |step|
      - if step.active
        - completed = false
      - elsif completed == true
        - step.active = true
      .step.d-flex.align-items-center
        = step
        - if step.label
          -# if steps.last != step
          .step-gap.short{class: step.active ? 'active' : ''}
          .step-label{class: step.active ? 'active' : ''}= step.label
      - if steps.last == step
        .flex-grow-1
      - elsif completed
        .step-gap.active
      - else
        .step-gap
- elsif @label_position == 'under'
  .progress-steps.d-flex.align-items-center.label-under
    - if @width != 'full'
      .flex-grow-1
    - steps.each do |step|
      .step
        = step
        - if step.label
          .step-label{class: step.active ? 'active' : ''}= step.label
      - if steps.last == step
        - if @width != 'full'
          .flex-grow-1
      - else
        .step-gap
- else
  .progress-steps.d-flex.align-items-center
    -#.flex-grow-1
    - steps.each do |step|
      .step.d-flex.align-items-center
        = step
        - if step.label
          .step-gap.short{class: step.active ? 'active' : ''}
          .step-label{class: step.active ? 'active' : ''}= step.label
      - if steps.last == step
        -#.flex-grow-1
      - else
        .step-gap


HAML

  def initialize(mode: 'progress', label_position: 'inline', width: 'full')
    @mode = mode.to_s
    @label_position = label_position.to_s
    @width = width
  end
end
