module TestCaseManagement
  module SafeAttributes
    def safe_attribute_names(user=nil)
      names = super
      names << "project_id" if new_record?
      names
    end

    def safe_attributes=(attrs, user=User.current)
      if attrs.respond_to?(:to_unsafe_hash)
        attrs = attrs.to_unsafe_hash
      end

      @attributes_set_by = user
      return unless attrs.is_a?(Hash)

      attrs = attrs.deep_dup

      if (given_project = attrs.delete("project_id")) && safe_attribute?("project_id")
        if given_project.is_a?(String) && !/^\d*$/.match?(given_project)
          given_project_id = Project.find_by_identifier(given_project).try(:id)
        else
          given_project_id = given_project.to_i
        end
        if allowed_target_projects(user).where(:id => given_project_id).exists?
          self.project_id = given_project_id
        end
      end

      assign_attributes attrs
    end

    def assign_attributes(new_attributes, *args)
      return if new_attributes.nil?

      attrs = new_attributes.dup
      attrs.stringify_keys!

      %w(project project_id).each do |attr|
        if attrs.has_key?(attr)
          send "#{attr}=", attrs.delete(attr)
        end
      end

      migrate_legacy_attributes!(attrs)

      super attrs, *args
    end

    # TestCaseExecution renamed its owner (user -> executor) and defect link
    # (issue -> defect_issue) columns and replaced the boolean `result` with a
    # status. Legacy producers (imports, old specs) still supply the old keys;
    # map them onto the new columns so they do not raise UnknownAttributeError.
    def migrate_legacy_attributes!(attrs)
      return unless respond_to?(:executor_id)

      if (v = attrs.delete("user") || attrs.delete("user_id"))
        self.executor_id = (v.respond_to?(:id) ? v.id : v.to_i)
      end

      if (v = attrs.delete("issue") || attrs.delete("issue_id"))
        self.defect_issue_id =
          if v.respond_to?(:id)
            v.id
          else
            (v.respond_to?(:blank?) && v.blank?) ? nil : v.to_i
          end
      end

      if attrs.key?("result")
        attrs["status_id"] ||= legacy_result_status_id(attrs.delete("result"))
      end
    end

    def legacy_result_status_id(value)
      label =
        case value
        when true,  'true'      then 'passed'
        when false, 'false'     then 'failed'
        else value.to_s.strip.downcase
        end
      status = TestExecutionStatus.canonical(label) ||
               TestExecutionStatus.canonical(%w[succeed success pass passed ok].include?(label) ? 'passed' : label) ||
               TestExecutionStatus.canonical(%w[fail failure incorrect].include?(label) ? 'failed' : label)
      status && status.id
    end

    def attributes=(new_attributes)
      assign_attributes new_attributes
    end
  end
end
