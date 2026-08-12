module TestCaseManagement
  module InheritIssuePermissions
    # The plugin's own permissions are the primary authority. The model classes
    # pass their permission key (e.g. :view_test_cases) so issue permissions are
    # no longer a precondition for reading plugin content.

    # The association used to attribute ownership. TestPlan/TestCase use +user+;
    # TestCaseExecution renamed it to +executor+. Concrete models may override
    # owner_ref to point at their actual owning association.
    def owner_ref
      :user
    end

    def visible?(user=User.current, permission: :view_test_cases)
      owner = send(owner_ref)
      user.allowed_to?(permission, project) do |role, allowed_user|
        if allowed_user.logged?
          case role.issues_visibility
          when "all"
            true
          when "default"
            # No private state exists for test content; "default" behaves like all.
            true
          when "own"
            owner == allowed_user
          else
            false
          end
        else
          role.has_permission?(permission)
        end
      end
    end

    def editable?(user=User.current, edit_permission: :edit_test_cases)
      attributes_editable?(user, edit_permission: edit_permission)
    end

    def attributes_editable?(user=User.current, edit_permission: :edit_test_cases)
      user_permission?(user, edit_permission)
    end

    def deletable?(user=User.current, delete_permission: :delete_test_cases)
      user_permission?(user, delete_permission)
    end

    def ownable_users
      return [] if project.nil?

      users = project.assignable_users.to_a
      users.uniq.sort
    end

    def allowed_target_projects(user=User.current, scope=nil)
      # Decoupled from Issue allowed_target_projects to avoid issue-only gating.
      Project.visible(user).to_a
    end

    private

    def user_permission?(user, permission)
      if project && !project.active?
        perm = Redmine::AccessControl.permission(permission)
        return false unless perm && perm.read?
      end

      if user.admin?
        true
      else
        user.roles_for_project(project).any? do |role|
          role.has_permission?(permission)
        end
      end
    end

    def owned_only_by_visible_user
      owner = send(owner_ref)
      return true unless owner
      # The owning user (the record's +user+ or +executor+) must itself be a
      # visible, assignable user to the acting user. This is the generic
      # User#visible? check — NOT the record's plugin visibility, which would
      # wrongly depend on the owner holding the plugin view permission.
      errors.add(owner_ref, "Unownable User") unless owner.visible?(User.current)
    end

    module_function

    # Build a SQL condition that limits the query to projects/records the user
    # may access with the given plugin permission. +owner_column+ (default
    # +user_id+) is the column compared against the current user for "own"
    # visibility; TestCaseExecution passes +executor_id+.
    def visible_condition(user, options={}, permission: :view_test_cases, owner_column: :user_id)
      Project.allowed_to_condition(user, permission, options) do |role, allowed_user|
        sql =
          if allowed_user.id && allowed_user.logged?
            case role.issues_visibility
            when "all"
              "1=1"
            when "default"
              "1=1"
            when "own"
              "#{owner_column} = #{allowed_user.id}"
            else
              "1=0"
            end
          else
            "projects.is_public = (1=1)"
          end
        unless role.has_permission?(permission)
          sql = "1=0"
        end
        sql
      end
    end
  end
end
