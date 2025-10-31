# frozen_string_literal: true

class FixerGenerator < Rails::Generators::NamedBase
  source_root(File.expand_path("templates", __dir__))

  def create_fixer
    id = Dir["db/fixes/*.rb"].map { |f| File.basename(f, ".rb").split("_").first }.max.to_i + 1
    copy_file("fixer.rb", "db/fixes/#{id}_#{file_name}.rb", mode: :preserve)
  end
end
