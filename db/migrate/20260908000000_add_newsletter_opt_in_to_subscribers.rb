# Newsletter consent, split out from mere existence in the subscribers table.
#
# Until now a Subscriber row *was* the subscription: creating one submitted the
# HubSpot newsletter form, and Subscriber#sync_to_hubspot sent
# newsletter_subscription: true unconditionally. That held while the only way to
# become a subscriber was to ask to be one.
#
# It stopped holding when the row became the identity key for other things. A
# resident survey response requires one (election_survey_responses.subscriber_id
# is NOT NULL), so answering the survey subscribed you whatever you answered —
# and the survey asks "Subscribe to our newsletter" outright, then stored that
# answer in jsonb where nothing ever read it.
#
# Defaults to false so a new write path has to opt someone in deliberately
# rather than by forgetting to think about it.
class AddNewsletterOptInToSubscribers < ActiveRecord::Migration[8.1]
  def up
    add_column :subscribers, :newsletter_opt_in, :boolean, null: false, default: false

    # Everyone already on the list stays on it. They are in HubSpot receiving
    # mail today and we hold no record of them declining, so flipping them to
    # false here would be a silent mass unsubscribe on no evidence.
    execute "UPDATE subscribers SET newsletter_opt_in = TRUE"

    # ...except where a survey answer on file says no. That is the one place we
    # hold an explicit statement of intent, and it has been ignored since the
    # question shipped, so honouring it now is a correction rather than a
    # change of policy.
    #
    # Any "no" wins over a "yes" on another response: with two contradictory
    # answers and no way to rank them here, the safe reading of consent is the
    # one that leaves someone off the list.
    execute <<~SQL.squish
      UPDATE subscribers
      SET newsletter_opt_in = FALSE
      WHERE id IN (
        SELECT subscriber_id
        FROM warehouse.election_survey_responses
        WHERE LOWER(TRIM(answers ->> 'updates')) IN ('no', 'false')
      )
    SQL
  end

  def down
    remove_column :subscribers, :newsletter_opt_in
  end
end
