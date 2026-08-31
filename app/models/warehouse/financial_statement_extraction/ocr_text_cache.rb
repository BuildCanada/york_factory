require "digest"
require "fileutils"
require "json"
require "tempfile"

class Warehouse::FinancialStatementExtraction::OcrTextCache
  SCHEMA_VERSION = 1

  class << self
    def reset_statistics!
      statistics_mutex.synchronize { @statistics = Hash.new(0) }
    end

    def record(status)
      statistics_mutex.synchronize do
        @statistics ||= Hash.new(0)
        @statistics[status] += 1
        @statistics.dup
      end
    end

    private

    def statistics_mutex
      @statistics_mutex ||= Mutex.new
    end
  end

  def initialize(root:, source_path:, reporter: nil)
    @root = root.present? ? Pathname(root).expand_path : nil
    @source_path = Pathname(source_path).expand_path
    @reporter = reporter || ->(event) { warn(event.to_json) }
  end

  def fetch(page:, mode:, options:)
    return yield unless usable?

    computed = false
    computed_text = nil
    computing = false
    metadata = normalized_metadata(page:, mode:, options:)
    key = Digest::SHA256.hexdigest(JSON.generate(metadata))
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    if (text = read_entry(key, metadata))
      report("hit", key, metadata, started)
      return text
    end

    with_lock(key) do
      if (text = read_entry(key, metadata))
        report("hit_after_lock", key, metadata, started)
        return text
      end

      computing = true
      text = yield
      computing = false
      computed = true
      computed_text = text
      raise ArgumentError, "OCR cache values must be valid UTF-8 strings" unless
        text.is_a?(String) && text.encoding == Encoding::UTF_8 && text.valid_encoding?

      write_entry(key, metadata, text)
      report("miss", key, metadata, started)
      text
    end
  rescue SystemCallError => error
    raise if computing

    report("bypass", nil, { "page" => page, "mode" => mode, "error" => error.message }, started)
    computed ? computed_text : yield
  end

  private

  def usable?
    return false unless @root

    FileUtils.mkdir_p(@root)
    @root.directory? && @root.writable?
  rescue SystemCallError
    false
  end

  def normalized_metadata(page:, mode:, options:)
    {
      "schema_version" => SCHEMA_VERSION,
      "source_sha256" => source_sha256,
      "page" => Integer(page),
      "mode" => mode.to_s,
      "options" => deep_stringify_and_sort(options)
    }
  end

  def source_sha256
    @source_sha256 ||= Digest::SHA256.file(@source_path).hexdigest
  end

  def deep_stringify_and_sort(value)
    case value
    when Hash
      value.to_h { |key, child| [ key.to_s, deep_stringify_and_sort(child) ] }.sort.to_h
    when Array
      value.map { deep_stringify_and_sort(_1) }
    when Symbol
      value.to_s
    else
      value
    end
  end

  def entry_path(key)
    @root.join(key.first(2), "#{key}.json")
  end

  def lock_path(key)
    @root.join(key.first(2), "#{key}.lock")
  end

  def read_entry(key, metadata)
    payload = JSON.parse(entry_path(key).read)
    return unless payload == {
      "schema_version" => SCHEMA_VERSION,
      "key" => key,
      "metadata" => metadata,
      "text" => payload["text"]
    }

    text = payload["text"]
    text if text.is_a?(String) && text.encoding == Encoding::UTF_8 && text.valid_encoding?
  rescue Errno::ENOENT, JSON::ParserError, TypeError
    nil
  end

  def with_lock(key)
    path = lock_path(key)
    FileUtils.mkdir_p(path.dirname)
    File.open(path, File::RDWR | File::CREAT, 0o644) do |lock|
      lock.flock(File::LOCK_EX)
      yield
    ensure
      lock.flock(File::LOCK_UN)
    end
  end

  def write_entry(key, metadata, text)
    path = entry_path(key)
    FileUtils.mkdir_p(path.dirname)
    payload = {
      "schema_version" => SCHEMA_VERSION,
      "key" => key,
      "metadata" => metadata,
      "text" => text
    }
    Tempfile.create([ ".#{key}", ".tmp" ], path.dirname) do |temporary|
      temporary.binmode
      temporary.write(JSON.generate(payload))
      temporary.flush
      temporary.fsync
      File.rename(temporary.path, path)
    end
  end

  def report(status, key, metadata, started)
    elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1_000).round
    counts = self.class.record(status)
    @reporter.call(
      ocr_cache: status, cache_key: key, page: metadata["page"], mode: metadata["mode"],
      elapsed_ms: elapsed, counts:
    )
  rescue StandardError
    nil
  end
end
