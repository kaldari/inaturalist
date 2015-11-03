class Admin::DelayedJobsController < ApplicationController

  before_filter :authenticate_user!
  before_filter :admin_required

  layout "admin"

  def index
    redirect_to :active_admin_delayed_jobs
  end

  def active
    @jobs = Delayed::Job.possibly_active
  end

  def failed
    @jobs = Delayed::Job.failed.limit(100)
  end

  def pending
    @jobs = Delayed::Job.pending.limit(100)
  end

end