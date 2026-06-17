# Seed the TradingPost OAuth application.
#
# Run `bin/rails db:seed` to create/update the application.
# On first creation, this prints the client_id and client_secret — copy them
# into TradingPost's .env as YF_OAUTH_CLIENT_ID and YF_OAUTH_CLIENT_SECRET.

redirect_uri = ENV.fetch(
  "TRADING_POST_CALLBACK_URL",
  Rails.env.production? ? "https://buildcanada.com/api/auth/callback" : "http://localhost:5050/api/auth/callback"
)

app = Doorkeeper::Application.find_or_initialize_by(name: "TradingPost")

if app.new_record?
  app.redirect_uri = redirect_uri
  app.scopes = ""
  app.confidential = true
  app.trusted = true
  app.save!

  puts ""
  puts "Created TradingPost OAuth application:"
  puts "  Client ID:     #{app.uid}"
  puts "  Client Secret: #{app.secret}"
  puts "  Redirect URI:  #{app.redirect_uri}"
  puts ""
  puts "Add to TradingPost .env:"
  puts "  YF_OAUTH_CLIENT_ID=#{app.uid}"
  puts "  YF_OAUTH_CLIENT_SECRET=#{app.secret}"
  puts "  YF_OAUTH_BASE=#{Rails.env.production? ? 'https://auth.buildcanada.com' : 'http://localhost:3000'}"
  puts "  OAUTH_CALLBACK_URL=#{redirect_uri}"
  puts ""
else
  app.update!(redirect_uri: redirect_uri, trusted: true, scopes: "")
  puts "TradingPost OAuth application already exists (uid: #{app.uid})"
end
