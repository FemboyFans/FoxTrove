class String
  def truthy?
    match?(/\A(true|t|yes|y|on|1)\z/i)
  end

  def falsy?
    match?(/\A(false|f|no|n|off|0)\z/i)
  end
end
