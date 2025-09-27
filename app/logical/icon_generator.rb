module IconGenerator
  module_function

  ICON_FOLDER = Rails.public_path.join("icons")
  TARGET_FILE = Rails.public_path.join("icons.png")
  ICON_SIZE   = 64

  def run
    files = Dir.glob("#{ICON_FOLDER}/*.png").sort_by do |path|
      index, = File.basename(path).split("-")
      index.to_i
    end

    return if files.empty?

    thumbs = files.map do |file|
      thumb = Vips::Image.thumbnail(file, ICON_SIZE, height: ICON_SIZE, size: :force)
      thumb = thumb.bandjoin(255) unless thumb.has_alpha?
      thumb
    end

    icons = Vips::Image.arrayjoin(thumbs, across: 1)

    icons.pngsave(TARGET_FILE.to_s)
  end
end
