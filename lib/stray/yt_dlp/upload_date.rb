require "time"

module Stray
  module YtDlp
    module UploadDate
      def self.parse(date_str)
        return nil unless date_str

        Time.strptime(date_str, "%Y%m%d").utc
      end
    end
  end
end
