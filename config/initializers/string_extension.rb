class String
  def truthy?
    self.match?(/\A(true|t|yes|y|on|1)\z/i)
  end

  def falsy?
    self.match?(/\A(false|f|no|n|off|0)\z/i)
  end
end
