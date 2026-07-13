# Manage SSH deploy access on the Kamal server(s) in config/deploy.yml.
#
# Usage:
#   bin/rails server:list_keys
#   bin/rails server:add_key GITHUB=username          # fetch keys from github.com/username.keys
#   bin/rails server:add_key KEY=/path/to/key.pub     # or KEY="ssh-ed25519 AAAA... comment"
#   bin/rails server:remove_key MATCH=username        # matches comment/tag text; FORCE=1 skips prompt
#
# remove_key refuses to remove your own key (any key in ~/.ssh/*.pub or your
# ssh-agent) or to empty authorized_keys entirely, so you can't lock yourself out.
namespace :server do
  def deploy_ssh_targets
    config = YAML.load_file("config/deploy.yml")
    user = config.dig("ssh", "user") || "root"
    hosts = config["servers"].values.flat_map { |role| role.is_a?(Hash) ? role["hosts"] : role }.uniq
    hosts.map { |host| "#{user}@#{host}" }
  end

  def read_authorized_keys(target)
    lines = `ssh #{target} 'cat ~/.ssh/authorized_keys'`.lines.map(&:strip)
    abort "Could not read authorized_keys on #{target}" unless $?.success?
    lines.reject(&:empty?)
  end

  def write_authorized_keys(target, lines)
    cmd = "umask 077 && cat > ~/.ssh/authorized_keys.new && mv ~/.ssh/authorized_keys.new ~/.ssh/authorized_keys"
    IO.popen([ "ssh", target, cmd ], "w") { |io| io.puts lines }
    abort "Failed to write authorized_keys on #{target}" unless $?.success?
  end

  # The base64 blob (second field) uniquely identifies a key regardless of comment
  def key_blob(line) = line.split[1]

  def own_key_blobs
    candidates = `ssh-add -L 2>/dev/null`.lines
    candidates += Dir[File.expand_path("~/.ssh/*.pub")].map { |f| File.read(f) }
    candidates.filter_map { |line| key_blob(line.strip) if line.match?(/AAAA/) }.uniq
  end

  def format_key(line)
    parts = line.split
    "#{parts[0]} #{parts[1][0, 24]}... #{parts[2..].join(" ")}"
  end

  desc "List SSH keys authorized on the deploy server(s)"
  task :list_keys do
    deploy_ssh_targets.each do |target|
      puts "#{target}:"
      read_authorized_keys(target).each { |line| puts "  #{format_key(line)}" }
    end
  end

  desc "Add an SSH public key to the deploy server(s) (GITHUB=username or KEY=path-or-literal)"
  task :add_key do
    keys =
      if (github = ENV["GITHUB"])
        fetched = `curl -fsS https://github.com/#{github}.keys`
        abort "Could not fetch keys for github.com/#{github}" unless $?.success? && !fetched.strip.empty?
        fetched.lines.map { |line| "#{line.strip} github:#{github}" }
      elsif (key = ENV["KEY"])
        path = File.expand_path(key)
        [ File.exist?(path) ? File.read(path).strip : key.strip ]
      else
        abort "Usage: bin/rails server:add_key GITHUB=username | KEY=/path/to/key.pub | KEY=\"ssh-ed25519 AAAA... comment\""
      end

    keys.each do |key|
      unless key.match?(/\A(ssh-(ed25519|rsa|dss)|ecdsa-[\w.@-]+|sk-[\w.@-]+) AAAA\S+/)
        abort "Does not look like an SSH public key: #{key[0, 80]}"
      end
    end

    deploy_ssh_targets.each do |target|
      existing_blobs = read_authorized_keys(target).map { |line| key_blob(line) }
      new_keys = keys.reject { |key| existing_blobs.include?(key_blob(key)) }

      if new_keys.empty?
        puts "#{target}: already authorized, nothing to do"
        next
      end

      IO.popen([ "ssh", target, "cat >> ~/.ssh/authorized_keys" ], "w") { |io| io.puts new_keys }
      abort "Failed to add key on #{target}" unless $?.success?
      new_keys.each { |key| puts "#{target}: added #{format_key(key)}" }
    end
  end

  desc "Remove an SSH key from the deploy server(s) by matching text (MATCH=username, FORCE=1 to skip prompt)"
  task :remove_key do
    pattern = ENV["MATCH"] || ENV["GITHUB"]
    abort "Usage: bin/rails server:remove_key MATCH=username" unless pattern

    own_blobs = own_key_blobs

    deploy_ssh_targets.each do |target|
      lines = read_authorized_keys(target)
      matches = lines.select { |line| line.downcase.include?(pattern.downcase) }

      if matches.empty?
        puts "#{target}: no keys match #{pattern.inspect}"
        next
      end

      matches.each do |line|
        if own_blobs.include?(key_blob(line))
          abort "#{target}: refusing to remove your own key (#{format_key(line)}). " \
            "It matches a key in ~/.ssh or your ssh-agent — removing it would lock you out."
        end
      end

      if matches.size == lines.size
        abort "#{target}: refusing to remove every authorized key — that would lock everyone out"
      end

      puts "#{target}: will remove #{matches.size} key(s):"
      matches.each { |line| puts "  #{format_key(line)}" }

      unless ENV["FORCE"] == "1"
        print "Remove? [y/N] "
        abort "Aborted" unless $stdin.gets&.strip&.downcase == "y"
      end

      write_authorized_keys(target, lines - matches)
      puts "#{target}: removed #{matches.size} key(s)"
    end
  end
end
