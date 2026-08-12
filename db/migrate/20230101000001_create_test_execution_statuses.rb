class CreateTestExecutionStatuses < ActiveRecord::Migration[5.2]
  def self.up
    create_table :test_execution_statuses do |t|
      t.references :project, null: true, index: false
      t.string :key, null: false, limit: 64
      t.string :name, null: false, limit: 255
      t.string :category, null: false, limit: 64
      t.integer :position, null: false, default: 0
      t.string :color, limit: 32
      t.boolean :is_default, null: false, default: false
      t.boolean :is_final, null: false, default: false
      t.timestamps
    end

    add_index :test_execution_statuses, :key, unique: true
    add_index :test_execution_statuses, [:project_id, :position]
    add_index :test_execution_statuses, [:project_id, :category]
    add_index :test_execution_statuses, :category

    # Seed the six canonical system statuses. The key is the stable internal
    # identifier; only the display name/color/category are meant to be edited.
    create_seeded_statuses
  end

  def self.down
    drop_table :test_execution_statuses
  end

  def self.create_seeded_statuses
    seeds = [
      { key: 'not_run',        name: 'Not run',       category: 'pending', position: 1, color: '#999999', is_default: true,  is_final: false },
      { key: 'in_progress',    name: 'In Progress',   category: 'running', position: 2, color: '#5cc2e2', is_default: false, is_final: false },
      { key: 'passed',         name: 'Passed',        category: 'passed',  position: 3, color: '#00aa33', is_default: false, is_final: true  },
      { key: 'failed',         name: 'Failed',        category: 'failed',  position: 4, color: '#dd0000', is_default: false, is_final: true  },
      { key: 'on_hold',        name: 'On hold',       category: 'blocked', position: 5, color: '#ff9900', is_default: false, is_final: false },
      { key: 'not_applicable', name: 'N/A',           category: 'skipped', position: 6, color: '#888888', is_default: false, is_final: true  },
    ]
    seeds.each do |seed|
      execute <<-SQL
        INSERT INTO test_execution_statuses
          (project_id, key, name, category, position, color, is_default, is_final, created_at, updated_at)
        VALUES
          (NULL, '#{seed[:key]}', '#{seed[:name]}', '#{seed[:category]}', #{seed[:position]},
           '#{seed[:color]}', #{seed[:is_default] ? "'t'" : "'f'"}, #{seed[:is_final] ? "'t'" : "'f'"},
           CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      SQL
    end
  end
end
