require "test_helper"

class Warehouse::Broadcasts::WebVttTest < ActiveSupport::TestCase
  test "parses, clamps, rebases, and renders cues" do
    source = <<~VTT
      WEBVTT

      cue-one
      00:00:08.000 --> 00:00:12.500 align:start
      before and after

      00:00:14.000 --> 00:00:18.000
      second cue
    VTT

    clipped = Warehouse::Broadcasts::WebVtt.clip(source, from: 10, to: 15)
    assert_equal [ 0.0, 4.0 ], clipped.map(&:start_seconds)
    assert_equal [ 2.5, 5.0 ], clipped.map(&:end_seconds)
    assert_equal "cue-one", clipped.first.identifier

    rendered = Warehouse::Broadcasts::WebVtt.render(clipped)
    assert_includes rendered, "00:00:00.000 --> 00:00:02.500 align:start"
    assert_equal clipped, Warehouse::Broadcasts::WebVtt.parse(rendered)
  end

  test "passages remove only the overlapping roll-up lines" do
    source = <<~VTT
      WEBVTT

      00:00:00.000 --> 00:00:05.000
      The chair calls

      00:00:05.000 --> 00:00:10.000
      The chair calls
      the meeting to order.

      00:00:10.000 --> 00:00:15.000
      the meeting to order.
      Welcome everyone.

      00:00:35.000 --> 00:00:40.000
      The chair calls
    VTT

    passages = Warehouse::Broadcasts::WebVtt.passages(source, duration: 60)
    assert_equal 2, passages.length
    assert_equal "The chair calls the meeting to order. Welcome everyone.", passages.first.text
    assert_equal "The chair calls", passages.second.text
    assert_equal 30, passages.second.start_seconds
  end

  test "binary UTF-8 French survives repeated parse and render cycles" do
    source = File.binread(file_fixture("cpac/caption_field2.vtt"))
    assert_equal Encoding::ASCII_8BIT, source.encoding

    rendered = 3.times.reduce(source) do |document, _iteration|
      Warehouse::Broadcasts::WebVtt.render(Warehouse::Broadcasts::WebVtt.parse(document))
    end
    cues = Warehouse::Broadcasts::WebVtt.parse(rendered)

    assert_includes rendered, "l’autodétermination"
    assert_includes rendered, "a été rédigé en français"
    assert_equal Encoding::UTF_8, rendered.encoding
    assert rendered.valid_encoding?
    assert_equal 3, cues.length
  end

  test "keeps FFmpeg roll-up text after a blank display row" do
    cues = Warehouse::Broadcasts::WebVtt.parse(File.binread(file_fixture("cpac/caption_field2.vtt")))

    assert_equal "l’autodétermination se produit.\nPar exemple, les endroits à", cues.second.text
    passage = Warehouse::Broadcasts::WebVtt.passages(cues, duration: 10).first
    assert_includes passage.text, "Par exemple, les endroits à"
  end
end
