class RemoteCollectionSubscriber
  def self.call(user:, url:)
    if existing = user.remote_collections.find_by(manifest_url: url)
      return existing.source
    end

    source = Source.create!(
      user: user,
      kind: :stray_collection,
      url: url,
      name: "Remote collection",
      external_id: Digest::SHA256.hexdigest(url)[0, 16],
      active: true
    )
    Follow.create!(user: user, source: source)
    RemoteCollection.create!(source: source, user: user, manifest_url: url)
    SourcePollJob.perform_later(source.id)
    source
  end
end
