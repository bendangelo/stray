class ChangeSourcePollIntervalDefaultToNil < ActiveRecord::Migration[8.1]
  def change
    change_column_default :sources, :poll_interval, from: 1800, to: nil
  end
end
