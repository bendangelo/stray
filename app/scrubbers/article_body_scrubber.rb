class ArticleBodyScrubber < Rails::HTML::PermitScrubber
  ALLOWED_TAGS = %w[
    p br hr h1 h2 h3 h4 h5 h6 ul ol li dl dt dd blockquote pre code em strong
    a img figure figcaption table thead tbody tr th td sup sub
    del ins mark small abbr cite q kbd samp var
  ].freeze

  ALLOWED_ATTRIBUTES = %w[href src alt title width height colspan rowspan
                          lang dir cite datetime].freeze

  def initialize
    super(prune: true)
    self.tags = ALLOWED_TAGS
    self.attributes = ALLOWED_ATTRIBUTES
  end
end
