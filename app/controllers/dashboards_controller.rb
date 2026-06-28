class DashboardsController < ApplicationController
  before_action :sync_local_runtime_sessions, only: :show

  def show
    @run = Run.current
    @session_sidebar = Run.session_sidebar_locals(selected_run: @run)
    @runs = @session_sidebar.fetch(:runs)
    @passport_tree = @run&.passport_tree
    @selected_passport = @passport_tree&.selected_passport(params[:passport_id])
    @tool_actions = @run&.tool_actions_for_display || []
    @panel = %w[passport tools audit].include?(params[:panel]) ? params[:panel] : nil

    render "runs/show" if @run.present?
  end

  private

  def sync_local_runtime_sessions
    return if Rails.env.test?

    ObservedRuntimeSessions::LocalProcessSyncer.sync_if_stale!
  end
end
