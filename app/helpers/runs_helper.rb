module RunsHelper
  KILLED_SESSION_STATUSES = %w[interrupted].freeze

  def session_sidebar_project_groups(runs)
    runs.to_a.group_by { |run| session_sidebar_project_path(run) }.map do |project_path, project_runs|
      visible_runs, killed_runs = project_runs.partition { |run| !session_sidebar_killed_run?(run) }

      {
        name: session_sidebar_project_name(project_runs.first),
        path: project_path,
        runs: visible_runs,
        killed_runs: killed_runs,
        total_runs: project_runs.size
      }
    end
  end

  def session_sidebar_killed_run?(run)
    run.status.in?(KILLED_SESSION_STATUSES)
  end

  def session_sidebar_project_name(run)
    path = run.project_path.to_s
    Pathname.new(path).basename.to_s.presence || path.presence || "unknown project"
  rescue StandardError
    run.project_path.presence || "unknown project"
  end

  def session_sidebar_project_path(run)
    run.project_path.presence || "unknown path"
  end

  def session_sidebar_run_title(run)
    title = run.display_title.to_s
    project_name = session_sidebar_project_name(run)
    runtime_label = run.runtime_label

    return runtime_label if title.blank?
    return runtime_label if title == project_name
    return runtime_label if title.match?(/\A#{Regexp.escape(runtime_label)}\s*:\s*#{Regexp.escape(project_name)}\z/i)
    return runtime_label if title.match?(/\A#{Regexp.escape(run.runtime_name)}\s*:\s*#{Regexp.escape(project_name)}\z/i)

    title
  end

  def session_sidebar_run_metadata(run)
    session_id = run.runtime_session_id.presence || "demo-run-#{run.id}"
    return session_id if session_sidebar_run_title(run).casecmp?(run.runtime_label)

    "#{run.runtime_label} / #{session_id}"
  end
end
