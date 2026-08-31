require "digest"
require "json"
require "pathname"

class Warehouse::InstitutionRelease::Recipe
  class RecipeError < StandardError; end

  attr_reader :path, :version

  def initialize(path)
    @path = Pathname(path).expand_path
    @payload = JSON.parse(@path.read)
    @version = @payload.fetch("release_version")
    validate!
  rescue Errno::ENOENT, JSON::ParserError, KeyError, Date::Error, TypeError => error
    raise RecipeError, "invalid release recipe: #{error.message}"
  end

  def municipality_paths
    entries("municipality_manifests")
  end

  def first_nations_path
    entry("first_nations_manifest")
  end

  def first_nations_assets_path
    entry("first_nations_asset_inventory")
  end

  def csd_inventory_path
    entry("csd_inventory")
  end

  def csd_authority_paths
    entries("csd_authority_crosswalks")
  end

  def asset_root
    resolve_path(@payload.fetch("asset_root"))
  end

  def sha256
    Digest::SHA256.file(path).hexdigest
  end

  private

  def validate!
    Date.iso8601(version)
    files = municipality_paths + [ first_nations_path, first_nations_assets_path, csd_inventory_path ] +
      csd_authority_paths
    raise RecipeError, "municipality_manifests must not be empty" if municipality_paths.empty?
    raise RecipeError, "csd_authority_crosswalks must not be empty" if csd_authority_paths.empty?
    raise RecipeError, "release recipe contains duplicate input paths" unless files.uniq.length == files.length

    raise RecipeError, "asset_root is not a directory: #{asset_root}" unless asset_root.directory?
  end

  def entries(key)
    Array(@payload.fetch(key)).map { |row| verified_path(row, key) }
  end

  def entry(key)
    verified_path(@payload.fetch(key), key)
  end

  def verified_path(row, key)
    raise RecipeError, "#{key} entries require path and sha256" unless row.is_a?(Hash)

    candidate = resolve_path(row.fetch("path"))
    expected = row.fetch("sha256")
    raise RecipeError, "missing recipe input: #{candidate}" unless candidate.file?
    unless expected.match?(/\A[0-9a-f]{64}\z/) && Digest::SHA256.file(candidate).hexdigest == expected
      raise RecipeError, "checksum mismatch for recipe input: #{candidate}"
    end
    candidate
  end

  def resolve_path(value)
    candidate = Pathname(value)
    candidate = path.dirname.join(candidate) unless candidate.absolute?
    candidate.expand_path
  end
end
