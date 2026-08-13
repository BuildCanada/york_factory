#!/usr/bin/env ruby

require "json"
require "optparse"
require "securerandom"
require "tmpdir"

DEFAULT_PATTERN = "account_overview_analytics*.csv"

def signature(path)
  stat = File.stat(path)
  { "size" => stat.size, "mtime" => stat.mtime.to_f, "ino" => stat.ino }
rescue Errno::ENOENT
  nil
end

def matching_files(directory, pattern)
  Dir.glob(File.join(directory, pattern)).select { |path| File.file?(path) }.sort
end

def parse_options(arguments, wait: false)
  options = {
    pattern: DEFAULT_PATTERN,
    timeout: 90.0,
    interval: 1.0
  }

  OptionParser.new do |parser|
    parser.on("--dir PATH", "Download directory") { |value| options[:directory] = value }
    parser.on("--pattern GLOB", "CSV filename glob") { |value| options[:pattern] = value }
    if wait
      parser.on("--checkpoint PATH", "Checkpoint returned by mark") { |value| options[:checkpoint] = value }
      parser.on("--timeout SECONDS", Float, "Maximum wait (default: 90)") { |value| options[:timeout] = value }
      parser.on("--interval SECONDS", Float, "Poll interval (default: 1)") { |value| options[:interval] = value }
    end
  end.parse!(arguments)

  options
end

def mark(arguments)
  options = parse_options(arguments)
  abort "Missing --dir" unless options[:directory]

  directory = File.expand_path(options[:directory])
  abort "Download directory does not exist: #{directory}" unless Dir.exist?(directory)

  state = {
    "directory" => directory,
    "pattern" => options[:pattern],
    "started_at" => Time.now.to_f,
    "baseline" => matching_files(directory, options[:pattern]).to_h { |path| [ path, signature(path) ] }
  }
  checkpoint = File.join(Dir.tmpdir, "x-analytics-download-#{SecureRandom.hex(12)}.json")
  File.open(checkpoint, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
    file.write(JSON.generate(state))
  end

  puts JSON.generate(checkpoint:, existing_files: state["baseline"].length)
end

def recent_partial_download?(state)
  partial_pattern = state.fetch("pattern").sub(/\.csv\z/, "*.crdownload")
  matching_files(state.fetch("directory"), partial_pattern).any? do |path|
    File.mtime(path).to_f >= state.fetch("started_at")
  end
end

def new_candidates(state)
  matching_files(state.fetch("directory"), state.fetch("pattern")).filter do |path|
    current = signature(path)
    baseline = state.fetch("baseline")[path]
    current && current["mtime"] >= state.fetch("started_at") && current != baseline
  end
end

def wait(arguments)
  options = parse_options(arguments, wait: true)
  abort "Missing --checkpoint" unless options[:checkpoint]
  abort "--timeout must be positive" unless options[:timeout].positive?
  abort "--interval must be positive" unless options[:interval].positive?

  checkpoint = File.expand_path(options[:checkpoint])
  state = JSON.parse(File.read(checkpoint))
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + options[:timeout]
  stable_path = nil
  stable_signature = nil

  loop do
    candidates = new_candidates(state)
    if candidates.length > 1
      warn JSON.generate(error: "ambiguous_download", files: candidates)
      return 3
    end

    candidate = candidates.first
    current_signature = signature(candidate) if candidate
    if candidate && current_signature["size"].positive? && !recent_partial_download?(state)
      if candidate == stable_path && current_signature == stable_signature
        puts JSON.generate(file: candidate, bytes: current_signature["size"])
        return 0
      end

      stable_path = candidate
      stable_signature = current_signature
    else
      stable_path = nil
      stable_signature = nil
    end

    break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

    sleep options[:interval]
  end

  warn JSON.generate(error: "download_timeout", timeout_seconds: options[:timeout])
  2
rescue Errno::ENOENT, JSON::ParserError, KeyError => error
  warn JSON.generate(error: "invalid_checkpoint", details: error.message)
  4
ensure
  File.delete(checkpoint) if checkpoint && File.file?(checkpoint)
end

command = ARGV.shift
status = case command
when "mark"
  mark(ARGV)
  0
when "wait"
  wait(ARGV)
else
  warn "Usage: guard_x_download.rb mark --dir PATH | wait --checkpoint PATH [--timeout SECONDS]"
  1
end

exit status
