# Small server-rendered SVG charts for the developer console and admin usage
# views. No JavaScript: each bar carries a <title> tooltip, and every chart
# comes with its numbers as a table (in a <details>), so nothing is read from
# the picture alone. One series per chart, in one colour; the chart's
# heading names it.
module UsageChartsHelper
  CHART_WIDTH = 640
  CHART_HEIGHT = 140
  AXIS = 18

  # A column chart of [[label, value], ...] (oldest first). `unit` names the
  # value in tooltips and the table ("units", "requests").
  def usage_column_chart(points, title:, unit:, label_every: nil)
    max = [ points.map(&:last).max.to_i, 1 ].max
    count = [ points.size, 1 ].max
    slot = CHART_WIDTH.to_f / count
    bar = [ [ slot - 2, 1 ].max, 24 ].min
    plot = CHART_HEIGHT - AXIS
    label_every ||= [ (count / 6.0).ceil, 1 ].max

    bars = points.each_with_index.map do |(label, value), i|
      h = value.to_i.zero? ? 0 : [ (value.to_f / max * (plot - 4)).round(1), 1 ].max
      x = (i * slot + (slot - bar) / 2).round(1)
      tip = "#{label}: #{number_with_delimiter(value.to_i)} #{unit}"
      # A hit area as tall as the plot, so short bars are easy to hover.
      tag.g(class: "usage-bar") do
        safe_join([
          tag.rect(x: (i * slot).round(1), y: 0, width: slot.round(1), height: plot, fill: "transparent"),
          (h.positive? ? tag.path(d: column_path(x, plot, bar, h), class: "usage-bar-fill") : "".html_safe),
          tag.title(tip)
        ])
      end
    end
    labels = points.each_with_index.filter_map do |(label, _), i|
      next unless (i % label_every).zero? || i == count - 1

      tag.text(label, x: (i * slot + slot / 2).round(1), y: CHART_HEIGHT - 4, "text-anchor": "middle", class: "usage-axis-label")
    end
    svg = tag.svg(viewBox: "0 0 #{CHART_WIDTH} #{CHART_HEIGHT}", role: "img", class: "usage-chart",
      "aria-label": "#{title}: #{points.size} bars, highest #{number_with_delimiter(points.map(&:last).max.to_i)} #{unit}") do
      safe_join([
        tag.line(x1: 0, y1: plot, x2: CHART_WIDTH, y2: plot, class: "usage-baseline"),
        tag.text("#{number_with_delimiter(max)} #{unit}", x: 2, y: 10, class: "usage-axis-label"),
        *bars, *labels
      ])
    end
    tag.figure(class: "usage-figure") do
      safe_join([ tag.figcaption(title, class: "label"), svg, usage_table(points, unit:) ])
    end
  end

  # A 24-point sparkline (the keys table's last 24 hours).
  def usage_sparkline(values, label:)
    max = [ values.max.to_i, 1 ].max
    w = 96
    h = 20
    step = values.size > 1 ? w.to_f / (values.size - 1) : w
    points = values.each_with_index.map { |v, i| "#{(i * step).round(1)},#{(h - 2 - v.to_f / max * (h - 4)).round(1)}" }.join(" ")
    tag.svg(viewBox: "0 0 #{w} #{h}", width: w, height: h, role: "img", class: "usage-sparkline",
      "aria-label": "#{label}: #{number_with_delimiter(values.sum)} units in 24 hours") do
      safe_join([ tag.polyline(points:, fill: "none"), tag.title("#{number_with_delimiter(values.sum)} units in the last 24 hours") ])
    end
  end

  def usage_flag_badges(flags)
    labels = { spike: "10× spike", throttled: "Many 429s", errors: "Mostly 4xx", over_quota: "Over quota", near_quota: "Near quota", drift: "Edge drift" }
    safe_join(flags.map { |f| tag.span(labels.fetch(f, f.to_s), class: [ "badge", f.in?(%i[spike over_quota drift]) ? "badge-red" : "badge-yellow" ]) }, " ")
  end

  private

  # A column rising from the baseline with 4px rounded top corners.
  def column_path(x, base, width, height)
    r = [ 4, width / 2, height ].min
    top = base - height
    "M#{x},#{base} V#{(top + r).round(1)} Q#{x},#{top.round(1)} #{(x + r).round(1)},#{top.round(1)} " \
      "H#{(x + width - r).round(1)} Q#{(x + width).round(1)},#{top.round(1)} #{(x + width).round(1)},#{(top + r).round(1)} V#{base} Z"
  end

  def usage_table(points, unit:)
    tag.details(class: "usage-table") do
      safe_join([
        tag.summary("Show as a table"),
        tag.table do
          safe_join([
            tag.thead(tag.tr(safe_join([ tag.th("Period"), tag.th(unit.capitalize) ]))),
            tag.tbody(safe_join(points.map { |label, value| tag.tr(safe_join([ tag.td(label), tag.td(number_with_delimiter(value.to_i)) ])) }))
          ])
        end
      ])
    end
  end
end
