# Creates or updates the Doorkeeper application for the Build Canada member app
# platform (buildcanada.app). It is a confidential, trusted, first-party client
# with one exact callback and the `public identity` scopes.
#
#   MEMBER_APPS_CALLBACK_URL=https://buildcanada.app/auth/york/callback \
#     bin/rails member_apps:oauth_application
#
# The client id and secret print only when the application is first created.
namespace :member_apps do
  desc "Create or update the member app platform OAuth application"
  task oauth_application: :environment do
    callback = ENV.fetch("MEMBER_APPS_CALLBACK_URL", "https://buildcanada.app/auth/york/callback")
    app = Doorkeeper::Application.find_or_initialize_by(name: "Build Canada member apps")
    created = app.new_record?
    app.assign_attributes(redirect_uri: callback, scopes: "public identity", confidential: true, trusted: true)
    app.save!

    if created
      puts "Created the member apps OAuth application."
      puts "  YORK_CLIENT_ID=#{app.uid}"
      puts "  YORK_CLIENT_SECRET=#{app.secret}"
    else
      puts "Updated the member apps OAuth application (uid #{app.uid}); the secret is unchanged."
    end
    puts "  YORK_REDIRECT_URI=#{app.redirect_uri}"
  end
end
