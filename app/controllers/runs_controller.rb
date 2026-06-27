class RunsController < ApplicationController
  before_action :sync_local_runtime_sessions, only: :show

  def create
    runtime_name = RuntimeAdapters::Registry.normalize_name(params[:runtime_name])
    run = Run.active.where(runtime_name: runtime_name).latest_first.first ||
      RuntimeAdapters::ScriptedDemo.start!(runtime_name: runtime_name, project_path: Rails.root.to_s)

    redirect_to run_path(run)
  rescue ArgumentError => error
    redirect_to root_path, alert: error.message
  end

  def show
    @run = Run.find(params[:id])
    @session_sidebar = Run.session_sidebar_locals(selected_run: @run)
    @runs = @session_sidebar.fetch(:runs)
    @passport_tree = @run.passport_tree
    @selected_passport = @passport_tree.selected_passport(params[:passport_id])
    @panel = %w[passport audit].include?(params[:panel]) ? params[:panel] : nil
  end

  private

  def sync_local_runtime_sessions
    return if Rails.env.test?

    ObservedRuntimeSessions::LocalProcessSyncer.sync_if_stale!
  end
end
