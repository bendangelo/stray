module Stray
  module YtDlp
    class Error < StandardError; end
    class Timeout < Error; end
    class NotFound < Error; end
    class ExtractionFailed < Error; end
  end
end
