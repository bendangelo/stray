Rails.application.config.to_prepare do
  Stray::ExtractorRegistry.reset!
  Stray::ExtractorRegistry.register(Stray::Extractors::YoutubeRss)
  Stray::ExtractorRegistry.register(Stray::Extractors::RssAtom)
  Stray::ExtractorRegistry.register(Stray::Extractors::YtDlp)
end
