class ProjectUser < ActiveRecord::Base
  
  belongs_to :project
  belongs_to :user
  auto_subscribes :user, :to => :project
  
  after_save :check_role, :remove_updates, :subscribe_to_assessment_sections_later
  after_destroy :remove_updates
  validates_uniqueness_of :user_id, :scope => :project_id, :message => "already a member of this project"
  validates_rules_from :project, :rule_methods => [:has_time_zone?]
  
  CURATOR_CHANGE_NOTIFICATION = "curator_change"
  ROLES = %w(curator manager)
  ROLES.each do |role|
    const_set role.upcase, role
    scope role.pluralize, where(:role => role)
  end

  notifies_subscribers_of :project, :on => :save, :notification => CURATOR_CHANGE_NOTIFICATION, 
    :include_notifier => true,
    # don't bother queuing this if there's no relevant role change
    :queue_if => Proc.new {|pu|
      pu.role_changed? && (ROLES.include?(pu.role) || pu.user_id == pu.project.user_id)
    },
    # check to make sure role status hasn't changed since queuing
    :if => Proc.new {|pu| ROLES.include?(pu.role) || pu.user_id == pu.project.user_id}

  def to_s
    "<ProjectUser #{id} project: #{project_id} user: #{user_id} role: #{role}>"
  end

  def project_observations
    project.project_observations.includes(:observation).where("observations.user_id = ?", user_id).scoped
  end

  def remove_updates
    return true unless role_changed? && role.blank?
    Update.where(
      :notifier_type => "ProjectUser", 
      :notifier_id => id, 
      :resource_type => "Project", 
      :resource_id => project_id).destroy_all
    true
  end

  def subscribe_to_assessment_sections_later
    return true unless role_changed? && !role.blank?
    delay(:priority => USER_INTEGRITY_PRIORITY).subscribe_to_assessment_sections
    true
  end

  def subscribe_to_assessment_sections
    AssessmentSection.includes(:assessment).where("assessments.project_id = ?", project).find_each do |as|
      Subscription.create(:resource => as, :user => user)
    end
  end
  
  def has_time_zone?
    user.time_zone?
  end
  
  def is_curator?
    role == 'curator' || is_manager? || is_admin?
  end
  
  def is_manager?
    role == 'manager' || is_admin?
  end
  
  def is_admin?
    user_id == project.user_id
  end
  
  def update_observations_counter_cache
    update_attributes(:observations_count => project_observations.count)
  end
  
  # set taxa_count on project user, which is the number of taxa observed by this user, favoring the curator ident
  def update_taxa_counter_cache
    sql = <<-SQL
      SELECT count(DISTINCT COALESCE(i.taxon_id, o.taxon_id))
      FROM project_observations po
        JOIN observations o ON po.observation_id = o.id
        LEFT OUTER JOIN taxa ot ON ot.id = o.taxon_id
        LEFT OUTER JOIN identifications i ON po.curator_identification_id = i.id
        LEFT OUTER JOIN taxa it ON it.id = i.taxon_id
      WHERE
        po.project_id = #{project_id}
        AND o.user_id = #{user_id}
        AND (
          -- observer's ident taxon is species or lower
          ot.rank_level <= #{Taxon::SPECIES_LEVEL}
          -- curator's ident taxon is species or lower
          OR it.rank_level <= #{Taxon::SPECIES_LEVEL}
        )
    SQL
    update_attributes(:taxa_count => ProjectUser.connection.execute(sql)[0]['count'].to_i)
  end
  
  def check_role
    return true unless role_changed?
    if role_was.blank?
      Project.delay(:priority => USER_INTEGRITY_PRIORITY).update_curator_idents_on_make_curator(project_id, id)
    elsif role.blank?
      Project.delay(:priority => USER_INTEGRITY_PRIORITY).update_curator_idents_on_remove_curator(project_id, id)
    end
    true
  end
  
  def self.update_observations_counter_cache_from_project_and_user(project_id, user_id)
    return unless project_user = ProjectUser.first(:conditions => {
      :project_id => project_id, 
      :user_id => user_id
    })
    project_user.update_observations_counter_cache
  end
  
  def self.update_taxa_counter_cache_from_project_and_user(project_id, user_id)
    return unless project_user = ProjectUser.first(:conditions => {
      :project_id => project_id, 
      :user_id => user_id
    })
    project_user.update_taxa_counter_cache
  end
  
  def self.update_taxa_obs_and_observed_taxa_count_after_update_observation(observation_id, user_id)
    unless obs = Observation.find_by_id(observation_id)
      return
    end
    unless usr = User.find_by_id(user_id)
      return
    end
    obs.project_observations.each do |po|
      if project_user = ProjectUser.first(:conditions => {
        :project_id => po.project_id, 
        :user_id => user_id
      })
        project_user.update_taxa_counter_cache
        project_user.update_observations_counter_cache
        Project.update_observed_taxa_count(po.project_id)
      end
    end
  end
end
