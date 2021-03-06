class TagGroup < ActiveRecord::Base
  validates_uniqueness_of :name, case_sensitive: false

  has_many :tag_group_memberships, dependent: :destroy
  has_many :tags, through: :tag_group_memberships
  has_many :category_tag_groups, dependent: :destroy
  has_many :categories, through: :category_tag_groups
  has_many :tag_group_permissions, dependent: :destroy

  belongs_to :parent_tag, class_name: 'Tag'

  before_save :apply_permissions

  attr_accessor :permissions

  def tag_names=(tag_names_arg)
    DiscourseTagging.add_or_create_tags_by_name(self, tag_names_arg, unlimited: true)
  end

  def parent_tag_name=(tag_names_arg)
    if tag_names_arg.empty?
      self.parent_tag = nil
    else
      if tag_name = DiscourseTagging.tags_for_saving(tag_names_arg, Guardian.new(Discourse.system_user)).first
        self.parent_tag = Tag.find_by_name(tag_name) || Tag.create(name: tag_name)
      end
    end
  end

  def permissions=(permissions)
    @permissions = TagGroup.resolve_permissions(permissions)
  end

  def self.resolve_permissions(permissions)
    everyone_group_id = Group::AUTO_GROUPS[:everyone]
    full = TagGroupPermission.permission_types[:full]

    mapped = permissions.map do |group, permission|
      group_id = Group.group_id_from_param(group)
      permission = TagGroupPermission.permission_types[permission] unless permission.is_a?(Integer)

      return [] if group_id == everyone_group_id && permission == full

      [group_id, permission]
    end
  end

  def apply_permissions
    if @permissions
      tag_group_permissions.destroy_all
      @permissions.each do |group_id, permission_type|
        tag_group_permissions.build(group_id: group_id, permission_type: permission_type)
      end
      @permissions = nil
    end
  end

  def visible_only_to_staff
    # currently only "everyone" and "staff" groups are supported
    tag_group_permissions.count > 0
  end

  def self.allowed(guardian)
    if guardian.is_staff?
      TagGroup
    else
      category_permissions_filter = <<~SQL
        (id IN ( SELECT tag_group_id FROM category_tag_groups WHERE category_id IN (?))
        OR id NOT IN (SELECT tag_group_id FROM category_tag_groups))
        AND id NOT IN (SELECT tag_group_id FROM tag_group_permissions)
      SQL

      TagGroup.where(category_permissions_filter, guardian.allowed_category_ids)
    end
  end
end

# == Schema Information
#
# Table name: tag_groups
#
#  id            :integer          not null, primary key
#  name          :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  parent_tag_id :integer
#  one_per_topic :boolean          default(FALSE)
#
