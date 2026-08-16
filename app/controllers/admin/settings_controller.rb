module Admin
  class SettingsController < BaseController
    def show
      @setting = Setting.current
    end

    def update
      @setting = Setting.current
      permitted = setting_params

      [ :smtp_password, :ai_provider_api_key ].each do |secret_field|
        permitted.delete(secret_field) if permitted[secret_field].blank?
      end

      if @setting.update(permitted)
        redirect_to admin_settings_path, notice: "Settings updated"
      else
        render :show, status: :unprocessable_entity
      end
    end

    def download_model
      DownloadEmbeddingModelJob.perform_later
      redirect_to admin_settings_path, notice: "Downloading model in background."
    end

    private

    def setting_params
      params.require(:setting).permit(
        :instance_name, :instance_domain,
        :smtp_host, :smtp_port, :smtp_username, :smtp_password,
        :ai_provider_name, :ai_provider_url, :ai_provider_api_key,
        :llm_tagging_enabled, :llm_tagging_model,
        :zero_shot_threshold, :zero_shot_top_n, :embedding_model
      )
    end
  end
end
