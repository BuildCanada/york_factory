# Append-only audit log for key, account and admin changes
# (docs/public-interface-design.md §8.4). No foreign keys, so the history
# outlives the rows it describes. A trigger refuses UPDATE and DELETE, so
# append-only holds even if the application role is ever granted them.
class CreateAuditEvents < ActiveRecord::Migration[8.1]
  def up
    create_table :audit_events do |t|
      t.bigint :account_id
      t.bigint :actor_user_id
      t.string :actor_kind, null: false
      t.string :action, null: false
      t.string :subject_type
      t.bigint :subject_id
      t.inet :ip
      t.string :user_agent
      t.jsonb :metadata, null: false, default: {}
      t.timestamptz :created_at, null: false, default: -> { "now()" }
    end

    add_index :audit_events, %i[account_id created_at]
    add_index :audit_events, %i[subject_type subject_id created_at], name: "index_audit_events_on_subject"
    add_index :audit_events, %i[action created_at]
    add_check_constraint :audit_events,
      "actor_kind IN ('user','admin','system')", name: "audit_events_actor_kind"

    execute <<~SQL
      CREATE FUNCTION public.audit_events_append_only() RETURNS trigger
      LANGUAGE plpgsql AS $$
      BEGIN
        RAISE EXCEPTION 'audit_events is append-only';
      END;
      $$;

      CREATE TRIGGER audit_events_append_only
      BEFORE UPDATE OR DELETE ON public.audit_events
      FOR EACH ROW EXECUTE FUNCTION public.audit_events_append_only();
    SQL
  end

  def down
    drop_table :audit_events
    execute "DROP FUNCTION IF EXISTS public.audit_events_append_only()"
  end
end
