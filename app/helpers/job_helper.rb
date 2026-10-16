module JobHelper
  #
  # Columns for the job table on the app show page.
  #
  def job_columns
    [
      [ :shrink, :hide_sm, :nowrap, t("jobs.started") ],
      [ :shrink, :nowrap, t("jobs.state_label") ],
      [ :grow, t("jobs.action") ],
      [ :grow, t("jobs.outcome") ]
    ]
  end
end
