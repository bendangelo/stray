class Extractor
  def self.matches?(url)
    raise NotImplementedError
  end

  def self.handles_kind?(kind)
    false
  end

  def extract(url)
    raise NotImplementedError
  end

  def extract_feed(url)
    raise NotImplementedError
  end

  def enrich_tags(url)
    nil
  end
end
