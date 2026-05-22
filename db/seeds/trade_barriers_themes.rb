[
  "Food",
  "Occupational Health and Safety",
  "Construction",
  "Goods",
  "Labour Mobility",
  "Transport",
  "Registration Requirements"
].each do |name|
  TradeBarriers::Theme.create_or_find_by!(name: name)
end

puts "Seeded #{TradeBarriers::Theme.count} trade barrier themes"
