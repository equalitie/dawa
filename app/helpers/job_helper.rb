module JobHelper
  #
  # Columns for the job tables on the app show page.
  #
  # Type and Started are hidden below md/lg so the tables stay readable on a phone; the
  # state badge and outcome are what a narrow screen needs most.
  #
  def job_columns
    [
      [ :grow, :nowrap, t("jobs.type") ],
      [ :shrink, t("jobs.state_label") ],
      [ :shrink, :hide_sm, :nowrap, t("jobs.started") ],
      [ :grow, t("jobs.outcome") ],
      [ :shrink, t("jobs.log") ]
    ]
  end
end
