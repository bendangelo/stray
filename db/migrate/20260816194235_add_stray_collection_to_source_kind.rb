# frozen_string_literal: true
class AddStrayCollectionToSourceKind < ActiveRecord::Migration[8.1]
  # No schema change needed: sources.kind is a plain integer column.
  # This migration exists to document the new enum value 4 (:stray_collection).
  def up
    # no-op
  end

  def down
    # no-op
  end
end
