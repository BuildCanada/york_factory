require "test_helper"
require "digest"
require "tmpdir"

class Warehouse::InstitutionRelease::RecipeTest < ActiveSupport::TestCase
  test "resolves relative inputs and verifies every checksum" do
    Dir.mktmpdir do |directory|
      inputs = %w[municipality.json first-nations.json first-nations-assets.json csd.json authority.json]
      entries = inputs.to_h do |name|
        path = File.join(directory, name)
        File.write(path, name)
        [ name, { path: name, sha256: Digest::SHA256.file(path).hexdigest } ]
      end
      recipe_path = File.join(directory, "recipe.json")
      File.write(recipe_path, JSON.generate(
        release_version: "2026-08-27",
        asset_root: ".",
        municipality_manifests: [ entries.fetch("municipality.json") ],
        first_nations_manifest: entries.fetch("first-nations.json"),
        first_nations_asset_inventory: entries.fetch("first-nations-assets.json"),
        csd_inventory: entries.fetch("csd.json"),
        csd_authority_crosswalks: [ entries.fetch("authority.json") ]
      ))

      recipe = Warehouse::InstitutionRelease::Recipe.new(recipe_path)

      assert_equal "2026-08-27", recipe.version
      assert_equal Pathname(File.join(directory, "municipality.json")), recipe.municipality_paths.sole
      assert_equal Pathname(directory), recipe.asset_root
    end
  end

  test "rejects a changed input before importing anything" do
    Dir.mktmpdir do |directory|
      input = File.join(directory, "input.json")
      File.write(input, "changed")
      row = { path: input, sha256: "0" * 64 }
      recipe_path = File.join(directory, "recipe.json")
      File.write(recipe_path, JSON.generate(
        release_version: "2026-08-27", asset_root: directory,
        municipality_manifests: [ row ], first_nations_manifest: row,
        first_nations_asset_inventory: row, csd_inventory: row,
        csd_authority_crosswalks: [ row ]
      ))

      error = assert_raises(Warehouse::InstitutionRelease::Recipe::RecipeError) do
        Warehouse::InstitutionRelease::Recipe.new(recipe_path)
      end
      assert_includes error.message, "checksum mismatch"
    end
  end
end
