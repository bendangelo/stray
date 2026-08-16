class SetFirstUserAdmin < ActiveRecord::Migration[8.1]
  def up
    first_user = User.order(:id).first
    first_user&.update_column(:admin, true)
  end

  def down
    User.update_all(admin: false)
  end
end
