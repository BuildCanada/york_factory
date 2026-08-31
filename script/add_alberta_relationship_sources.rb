#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "optparse"
require "pathname"
require "time"

class AddAlbertaRelationshipSources
  CHANGE_SOURCE_URL =
    "https://open.alberta.ca/dataset/7b81986c-b05a-4b72-8f12-aec3a22970ae/resource/" \
      "939a15c5-59a2-44fe-8f65-09f7b7764a99/download/2023-lgcode.pdf"
  IMPROVEMENT_DISTRICT_CHANGE_SOURCE_URL =
    "https://open.alberta.ca/dataset/7b81986c-b05a-4b72-8f12-aec3a22970ae/resource/" \
      "0ef9bd1b-8e44-401c-b953-9420efc350be/download/2021-lgcode.pdf"
  SPECIAL_AREAS_SOURCE_URL = "https://www.alberta.ca/special-areas-board"

  SOURCES_BY_EDGE = {
    [ "ca/ab/diamond-valley", "succeeds", "ca/ab/black-diamond" ] => CHANGE_SOURCE_URL,
    [ "ca/ab/diamond-valley", "succeeds", "ca/ab/turner-valley" ] => CHANGE_SOURCE_URL,
    [ "ca/ab/bonnyville-no-87", "succeeds", "ca/ab/improvement-district-no-349" ] =>
      IMPROVEMENT_DISTRICT_CHANGE_SOURCE_URL,
    [ "ca/ab/special-areas-board", "controlled_by", "ca/ab" ] => SPECIAL_AREAS_SOURCE_URL
  }.freeze

  def initialize(manifest_path:, output_path:, transformed_at:)
    @manifest_path = Pathname(manifest_path).expand_path
    @output_path = Pathname(output_path).expand_path
    @transformed_at = Time.iso8601(transformed_at).utc
  end

  def run
    raise "missing manifest #{@manifest_path}" unless @manifest_path.file?
    raise "refusing to overwrite #{@output_path}" if @output_path.exist?

    manifest = JSON.parse(@manifest_path.read)
    raise "expected Alberta manifest" unless manifest.dig("province", "code") == "ab"

    relationships = manifest.fetch("relationships")
    relationships_by_key = relationships.group_by { |relationship| edge_key(relationship) }
    changes = SOURCES_BY_EDGE.map do |key, source_url|
      matches = relationships_by_key.fetch(key, [])
      raise "expected exactly one relationship #{key.join(' ')}; found #{matches.length}" unless matches.one?

      relationship = matches.first
      existing = relationship["source_url"]
      if existing && existing != source_url
        raise "conflicting source URL for #{key.join(' ')}: #{existing}"
      end
      relationship["source_url"] = source_url
      {
        "source_id" => key[0],
        "relationship_type" => key[1],
        "target_id" => key[2],
        "source_url" => source_url,
        "operation" => existing ? "verified_existing" : "added"
      }
    end

    manifest["relationship_source_augmentation"] = {
      "transformed_at" => @transformed_at.iso8601,
      "source_manifest_path" => @manifest_path.to_s,
      "source_manifest_sha256" => Digest::SHA256.file(@manifest_path).hexdigest,
      "changed_relationship_count" => changes.count { |change| change.fetch("operation") == "added" },
      "verified_relationship_count" => changes.count { |change| change.fetch("operation") == "verified_existing" },
      "relationships" => changes
    }

    FileUtils.mkdir_p(@output_path.dirname)
    @output_path.write(JSON.pretty_generate(manifest) << "\n")
    result = {
      "output" => @output_path.to_s,
      "output_sha256" => Digest::SHA256.file(@output_path).hexdigest,
      "changed_relationship_count" => manifest.dig("relationship_source_augmentation", "changed_relationship_count")
    }
    puts JSON.pretty_generate(result)
    result
  end

  private

  def edge_key(relationship)
    [ relationship.fetch("source_id"), relationship.fetch("relationship_type"), relationship.fetch("target_id") ]
  end
end

if $PROGRAM_NAME == __FILE__
  options = {}
  OptionParser.new do |parser|
    parser.banner = "Usage: add_alberta_relationship_sources.rb --manifest PATH --output PATH --transformed-at ISO8601"
    parser.on("--manifest PATH") { |value| options[:manifest_path] = value }
    parser.on("--output PATH") { |value| options[:output_path] = value }
    parser.on("--transformed-at ISO8601") { |value| options[:transformed_at] = value }
  end.parse!

  missing = %i[manifest_path output_path transformed_at].reject { |key| options[key] }
  abort "missing options: #{missing.join(', ')}" if missing.any?
  AddAlbertaRelationshipSources.new(**options).run
end
