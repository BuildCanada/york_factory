namespace :db do
  namespace :schema do
    task :dump do
      Dir.glob(Rails.root.join("db/*structure.sql")).each do |file|
        content = File.read(file)
        content.gsub!(/^CREATE SCHEMA public;$/, "CREATE SCHEMA IF NOT EXISTS public;")
        content.gsub!(/^CREATE SCHEMA warehouse;$/, "CREATE SCHEMA IF NOT EXISTS warehouse;")

        # Ensure PostGIS extension is created before any geography types are used
        unless content.include?("CREATE EXTENSION")
          content.sub!(
            /^SET default_tablespace/,
            "CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA public;\n\n\nSET default_tablespace"
          )
        end

        File.write(file, content)
      end
    end
  end
end
