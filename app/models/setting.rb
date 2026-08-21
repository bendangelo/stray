class Setting < ApplicationRecord
  ENCRYPTED_COLUMNS = %w[smtp_password ai_provider_api_key].freeze
  ENV_MAPPING = {
    instance_name:       "STRAY_INSTANCE_NAME",
    instance_domain:     "STRAY_INSTANCE_DOMAIN",
    smtp_host:           "STRAY_SMTP__HOST",
    smtp_port:           "STRAY_SMTP__PORT",
    smtp_username:       "STRAY_SMTP__USERNAME",
    smtp_password:       "STRAY_SMTP__PASSWORD",
    ai_provider_name:    "STRAY_AI_PROVIDER__NAME",
    ai_provider_url:     "STRAY_AI_PROVIDER__URL",
    ai_provider_api_key: "STRAY_AI_PROVIDER__API_KEY",
    zero_shot_threshold: "STRAY_ZERO_SHOT__THRESHOLD",
    zero_shot_top_n:     "STRAY_ZERO_SHOT__TOP_N",
    llm_tagging_enabled: "STRAY_LLM_TAGGING__ENABLED",
    llm_tagging_model:   "STRAY_LLM_TAGGING__MODEL",
    embedding_model:     "STRAY_EMBEDDING__MODEL",
    polite_crawl_delay:  "STRAY_POLITE_CRAWL_DELAY",
    publication_buffer_minutes: "STRAY_SOURCE_POLLING__PUBLICATION_BUFFER_MINUTES"
  }.freeze

  VALID_AI_PROVIDERS = %w[NONE OLLAMA OPENAI_COMPATIBLE].freeze

  encrypts :smtp_password, :ai_provider_api_key

  validates :ai_provider_name, inclusion: { in: VALID_AI_PROVIDERS }, allow_nil: true
  validate :smtp_completeness

  class << self
    def current
      find_or_create_by!(id: 1)
    rescue ActiveRecord::StatementInvalid
      nil
    end

    def get(key)
      column = key.to_sym
      raise ArgumentError, "Unknown setting: #{key}" unless ENV_MAPPING.key?(column)

      setting = current
      db_value = setting&.public_read(column)
      return db_value if db_value.present?

      env_value = ENV[ENV_MAPPING[column]]
      return env_value if env_value.present?

      yaml_default(column)
    end

    def set(key, value)
      column = key.to_sym
      raise ArgumentError, "Unknown setting: #{key}" unless ENV_MAPPING.key?(column)

      setting = current
      raise "Settings table not available" unless setting

      if column == :smtp_port || column == :publication_buffer_minutes
        setting.public_write(column, value.to_i)
      else
        setting.public_write(column, value.presence)
      end
      setting.save!
      setting.public_read(column)
    end
  end

  def public_read(column)
    public_send(column)
  end

  def public_write(column, value)
    public_send("#{column}=", value)
  end

  private

  def smtp_completeness
    return if smtp_host.blank?
    return if [ smtp_port, smtp_username, smtp_password ].all?(&:present?)

    errors.add(:smtp_host, "requires port, username, and password")
  end

  class << self
    private

    def yaml_default(column)
      return nil unless yaml_defaults

      yaml_defaults.dig(Rails.env.to_s, column.to_s)
    end

    def yaml_defaults
      return @yaml_defaults if defined?(@yaml_defaults)

      path = Rails.root.join("config/stray.yml")
      @yaml_defaults = File.exist?(path) ? YAML.safe_load(File.read(path), aliases: true) : nil
    rescue Errno::ENOENT
      @yaml_defaults = nil
    end
  end
end
