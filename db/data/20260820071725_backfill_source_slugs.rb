# frozen_string_literal: true

class BackfillSourceSlugs < ActiveRecord::Migration[8.1]
  TOKEN_LENGTH = 24

  def up
    Source.where(slug: nil).find_each do |source|
      source.update_column(:slug, SecureRandom.alphanumeric(TOKEN_LENGTH))
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
