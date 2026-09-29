# Accounts own public data API keys (docs/public-interface-design.md §4.1).
# Application data, so it lives in the public schema, not warehouse.
class CreateAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :accounts do |t|
      t.string :name, null: false
      t.string :kind, null: false, default: "personal"
      t.string :plan, null: false, default: "free"
      # Set only on personal accounts: the one user the account belongs to.
      t.references :personal_user, foreign_key: { to_table: :users }, index: { unique: true }
      t.string :plan_override
      t.timestamptz :plan_override_expires_at
      t.string :stripe_customer_id
      t.string :bifrost_customer_id
      t.timestamptz :suspended_at
      t.text :suspended_reason
      t.timestamptz :terms_accepted_at
      t.timestamps
    end

    add_check_constraint :accounts, "kind IN ('personal','organization')", name: "accounts_kind"
    add_check_constraint :accounts,
      "plan IN ('anonymous','free','internal','partner','paid')", name: "accounts_plan"
    add_check_constraint :accounts,
      "plan_override IS NULL OR plan_override IN ('anonymous','free','internal','partner','paid')",
      name: "accounts_plan_override"
    add_check_constraint :accounts,
      "kind <> 'personal' OR personal_user_id IS NOT NULL", name: "accounts_personal_has_user"

    create_table :account_memberships do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false, default: "member"
      t.timestamps
    end

    add_index :account_memberships, %i[account_id user_id], unique: true
    add_check_constraint :account_memberships,
      "role IN ('owner','admin','member')", name: "account_memberships_role"
  end
end
