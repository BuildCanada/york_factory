namespace :hubspot do
  desc "List existing marketing event properties in HubSpot"
  task list_event_properties: :environment do
    require "hubspot-api-client"

    client = Hubspot::Client.new(access_token: Rails.application.credentials.dig(:hubspot, :access_token))

    begin
      puts "Fetching existing marketing event properties from HubSpot..."

      response = client.api_request({
        method: "GET",
        path: "/crm/v3/properties/marketing_event"
      })

      # Parse the JSON response body
      parsed_response = JSON.parse(response.body)

      if parsed_response && parsed_response["results"]
        puts "\n=== EXISTING MARKETING EVENT PROPERTIES ==="
        puts "Found #{parsed_response["results"].size} properties:"
        puts "-" * 80

        parsed_response["results"].each do |property|
          puts "Name: #{property["name"]}"
          puts "Label: #{property["label"]}"
          puts "Type: #{property["type"]}"
          puts "Description: #{property["description"]}" if property["description"].present?
          if property["options"] && property["options"].any?
            puts "Options: #{property["options"].map { |opt| opt["label"] }.join(', ')}"
          end
          puts "-" * 40
        end
      else
        puts "No properties found or empty response"
        puts "Response body: #{response.body}"
      end

    rescue => e
      puts "Error: #{e.message}"
      puts "Error class: #{e.class}"
      puts "Backtrace: #{e.backtrace.first(5).join("\n")}" if e.backtrace
    end
  end

  desc "Create custom marketing event properties in HubSpot for Luma events"
  task create_event_properties: :environment do
    require "hubspot-api-client"

    client = Hubspot::Client.new(access_token: Rails.application.credentials.dig(:hubspot, :access_token))

    # First, get existing properties to check for conflicts
    puts "Checking existing marketing event properties..."
    existing_response = client.api_request({
      method: "GET",
      path: "/crm/v3/properties/marketing_event"
    })

    existing_properties = []
    if existing_response
      parsed_existing = JSON.parse(existing_response.body)
      if parsed_existing && parsed_existing["results"]
        existing_properties = parsed_existing["results"].map { |prop| prop["name"] }
        puts "Found #{existing_properties.size} existing properties"
      end
    end

    # Only create properties that don't exist in HubSpot's built-in properties
    # We'll use existing ones like:
    # - hs_external_event_id for luma_event_id
    # - hs_registrations for total_guests
    # - hs_attendees for checked_in_guests
    # - hs_start_datetime, hs_end_datetime for dates
    # - hs_event_name, hs_event_description, hs_event_url, etc.

    properties = [
      {
        name: "location_name",
        label: "Location Name",
        type: "string",
        description: "The name of the venue where the event takes place"
      },
      {
        name: "location_address",
        label: "Location Address",
        type: "string",
        description: "The full address of the event location"
      },
      {
        name: "timezone",
        label: "Timezone",
        type: "string",
        description: "The timezone for the event (e.g., America/Toronto)"
      },
      {
        name: "visibility",
        label: "Event Visibility",
        type: "enumeration",
        description: "The visibility setting for the event",
        options: [
          { label: "Public", value: "public" },
          { label: "Private", value: "private" },
          { label: "Unlisted", value: "unlisted" }
        ]
      },
      {
        name: "approved_guests",
        label: "Approved Guests",
        type: "number",
        description: "Number of guests approved to attend the event (different from total registrations)"
      },
      {
        name: "duration_hours",
        label: "Duration (Hours)",
        type: "number",
        description: "Duration of the event in hours"
      }
    ]

    puts "\nCreating custom marketing event properties in HubSpot..."
    puts "=" * 60

    properties.each do |prop_config|
      prop_name = prop_config[:name]

      # Skip if property already exists
      if existing_properties.include?(prop_name)
        puts "\n⏭️  Skipping #{prop_name} - property already exists"
        next
      end

      begin
        puts "\nCreating property: #{prop_name}"

        # Build the property request with required fields
        field_type = case prop_config[:type]
        when "string" then "text"
        when "number" then "number"
        when "enumeration" then "select"
        when "bool" then "booleancheckbox"
        when "datetime" then "date"
        else "text"
        end

        property_create = {
          name: prop_config[:name],
          label: prop_config[:label],
          type: prop_config[:type],
          fieldType: field_type,
          groupName: "marketingeventinformation",
          description: prop_config[:description]
        }

        # Add options for enumeration type
        if prop_config[:type] == "enumeration" && prop_config[:options]
          property_create[:options] = prop_config[:options]
        end

        response = client.api_request({
          method: "POST",
          path: "/crm/v3/properties/marketing_event",
          body: property_create
        })

        # Check if the response is actually successful
        if response && response.code.to_i >= 200 && response.code.to_i < 300
          parsed_response = JSON.parse(response.body)
          if parsed_response && parsed_response["name"]
            puts "✓ Successfully created property: #{prop_name}"
            puts "  Label: #{prop_config[:label]}"
            puts "  Type: #{prop_config[:type]}"
            puts "  HubSpot ID: #{parsed_response["name"]}"
          else
            puts "✗ Property creation response was invalid"
            puts "  Response: #{response.body}"
          end
        else
          puts "✗ Property creation failed with HTTP #{response.code}"
          puts "  Response: #{response.body}"
        end

      rescue => e
        puts "✗ Failed to create property #{prop_name}: #{e.message}"
        puts "  Error class: #{e.class}"
      end

      # Small delay to avoid rate limiting
      sleep(0.2)
    end

    puts "\n" + "=" * 60
    puts "Property creation completed!"
    puts "\nYou can now run 'rake hubspot:list_event_properties' to see all properties."
  end

  desc "Delete custom Luma event properties from HubSpot (use with caution!)"
  task delete_luma_properties: :environment do
    require "hubspot-api-client"

    client = Hubspot::Client.new(access_token: Rails.application.credentials.dig(:hubspot, :access_token))

    property_names = [
      "location_name",
      "location_address",
      "timezone",
      "visibility",
      "approved_guests",
      "duration_hours"
    ]

    puts "⚠️  WARNING: This will delete custom Luma event properties from HubSpot!"
    puts "Properties to delete: #{property_names.join(', ')}"
    puts "Are you sure? Type 'DELETE' to confirm:"

    confirmation = STDIN.gets.chomp

    unless confirmation == "DELETE"
      puts "Aborted - no properties were deleted."
      exit
    end

    puts "\nDeleting properties..."

    property_names.each do |prop_name|
      begin
        client.marketing.events.settings_api.archive(property_name: prop_name)
        puts "✓ Deleted property: #{prop_name}"
      rescue => e
        puts "✗ Failed to delete #{prop_name}: #{e.message}"
      end

      sleep(0.2)
    end

    puts "\nProperty deletion completed!"
  end
end
