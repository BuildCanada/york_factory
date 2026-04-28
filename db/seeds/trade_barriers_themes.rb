[
  "Food",
  "Occupational Health and Safety",
  "Construction",
  "Goods",
  "Labour Mobility",
  "Transport",
  "Registration Requirements"
].each do |name|
  TradeBarriers::Theme.find_or_create_by!(name: name)
end

puts "Seeded #{TradeBarriers::Theme.count} trade barrier themes"
