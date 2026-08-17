Rails.application.config.to_prepare do
  ExtractorRegistry.reset!
  ExtractorRegistry.register(Extractors::YoutubeRss)
  ExtractorRegistry.register(Extractors::RssAtom)
  ExtractorRegistry.register(Extractors::YtDlp)
  ExtractorRegistry.register(Extractors::RemoteCollection)
  ExtractorRegistry.register(Extractors::GenericPage)
end
