require "test_helper"

class SourceSecretTest < ActiveSupport::TestCase
  test "value is encrypted at rest" do
    source = sources(:youtube)
    secret = SourceSecret.create!(source: source, field_name: "token", value: "secret-key-123")

    raw = SourceSecret.connection.execute("SELECT value FROM source_secrets WHERE id = #{secret.id}").first["value"]
    assert_not_includes raw, "secret-key-123"
    assert_equal "secret-key-123", secret.reload.value
  end

  test "field_name must be unique per source" do
    source = sources(:youtube)
    SourceSecret.create!(source: source, field_name: "cookies", value: "cookie1")
    assert_raises(ActiveRecord::RecordInvalid) do
      SourceSecret.create!(source: source, field_name: "cookies", value: "cookie2")
    end
  end

  test "requires source_id and field_name" do
    secret = SourceSecret.new(field_name: "api_key", value: "x")
    assert_not secret.valid?
    assert_includes secret.errors[:source_id], "can't be blank"
  end
end
