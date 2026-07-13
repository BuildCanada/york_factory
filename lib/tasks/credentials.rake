# Fetches config/master.key from 1Password so the app can decrypt
# config/credentials.yml.enc.
#
# Requires the 1Password CLI (`brew install 1password-cli`) and access to the
# "Engineering" vault.
#
# Usage: bin/rails credentials:setup
namespace :credentials do
  MASTER_KEY_PATH = "config/master.key"
  OP_MASTER_KEY_REF = "op://Engineering/York Factory Master Key/credential"

  desc "Fetch config/master.key from 1Password"
  task :setup do
    if File.exist?(MASTER_KEY_PATH)
      puts "#{MASTER_KEY_PATH} already exists, nothing to do"
      next
    end

    unless system("command -v op > /dev/null")
      abort "1Password CLI not found. Install it with: brew install 1password-cli"
    end

    key = `op read "#{OP_MASTER_KEY_REF}"`.strip
    unless $?.success? && !key.empty?
      abort "Could not read the master key from 1Password. " \
        "Make sure you are signed in (`op signin`) and have access to the Engineering vault."
    end

    File.write(MASTER_KEY_PATH, key)
    File.chmod(0o600, MASTER_KEY_PATH)
    puts "Wrote #{MASTER_KEY_PATH}"
  end
end
