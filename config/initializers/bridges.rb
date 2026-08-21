Rails.application.config.to_prepare do
  Stray::BridgeRegistry.reset!
  Stray::BridgeRegistry.register(Bridges::Rumble)
  Stray::BridgeRegistry.register(Bridges::Bitchute)
  Stray::BridgeRegistry.register(Bridges::Odysee)
  Stray::BridgeRegistry.register(Bridges::Peertube)
  Stray::BridgeRegistry.register(Bridges::YoutubeRss)
  Stray::BridgeRegistry.register(Bridges::RssAtom)
  Stray::BridgeRegistry.register(Bridges::RemoteCollection)
  Stray::BridgeRegistry.register(Bridges::YtDlp)
  Stray::BridgeRegistry.register(Bridges::GenericList)
  Stray::BridgeRegistry.register(Bridges::GenericPage)
end
