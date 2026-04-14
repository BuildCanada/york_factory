class ReclassifyTeamMemberRoles < ActiveRecord::Migration[8.0]
  PRESERVED_ROLES = %w[board advisor volunteer].freeze

  def up
    preserved_list = PRESERVED_ROLES.map { |r| "'#{r}'" }.join(", ")

    # Team members connected to a memo become "memo_author" — unless they hold
    # a preserved role (board, advisor, volunteer), which takes precedence.
    execute <<~SQL
      UPDATE team_members
      SET role = 'memo_author'
      WHERE (role IS NULL OR role NOT IN (#{preserved_list}))
        AND id IN (
          SELECT author_id FROM memos WHERE author_id IS NOT NULL
          UNION
          SELECT co_author_id FROM memos WHERE co_author_id IS NOT NULL
        )
    SQL

    # Everyone left (no preserved role, not a memo author) becomes "employee".
    execute <<~SQL
      UPDATE team_members
      SET role = 'employee'
      WHERE role IS NULL OR role NOT IN (#{preserved_list}, 'memo_author')
    SQL
  end

  def down
    # Best-effort revert: collapse the new values back onto the prior default.
    execute "UPDATE team_members SET role = 'team' WHERE role IN ('memo_author', 'employee')"
  end
end
