class DashboardsController < ApplicationController
  after_action :enqueue_local_runtime_session_sync, only: :show

  def show
    @run = Run.current
    @session_sidebar = Run.session_sidebar_locals(selected_run: @run)
    @runs = @session_sidebar.fetch(:runs)
    @passport_tree = @run&.passport_tree
    @selected_passport = @passport_tree&.selected_passport(params[:passport_id])
    @tool_action_page = @run&.tool_action_page
    @panel = %w[passport tools audit].include?(params[:panel]) ? params[:panel] : nil

    render "runs/show" if @run.present?
  end

  private

  def enqueue_local_runtime_session_sync
    ObservedRuntimeSessions::LocalProcessSyncJob.perform_later
  end
end
