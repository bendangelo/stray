Rails.application.config.to_prepare do
  ExtractorRegistry.reset!
  ExtractorRegistry.register(Extractors::Rumble)
  ExtractorRegistry.register(Extractors::Bitchute)
  ExtractorRegistry.register(Extractors::Odysee)
  ExtractorRegistry.register(Extractors::Peertube)
  ExtractorRegistry.register(Extractors::YoutubeRss)
  ExtractorRegistry.register(Extractors::RssAtom)
  ExtractorRegistry.register(Extractors::RemoteCollection)
  ExtractorRegistry.register(Extractors::YtDlp)
  ExtractorRegistry.register(Extractors::GenericPage)
end
