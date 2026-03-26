Mobility.configure do
  plugins do
    backend :column
    active_record
    reader
    writer
    dirty
    fallbacks({ fr: :en })
  end
end
