module Archives
  ALL = [
    Archives::Tumblr,
    Archives::Custom,
  ].freeze

  def self.detect(file)
    archive_class = ALL.find { |clazz| clazz.handles_file(file) } || Archives::Manual
    archive_class.new(file)
  end
end
