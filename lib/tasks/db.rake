namespace :db do
  namespace :schema do
    task :dump do
      Dir.glob(Rails.root.join("db/*structure.sql")).each do |file|
        content = File.read(file)
        content.gsub!(/^CREATE SCHEMA public;$/, "CREATE SCHEMA IF NOT EXISTS public;")
        File.write(file, content)
      end
    end
  end
end
