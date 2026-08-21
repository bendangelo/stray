require "test_helper"

class Bridges::VideoMetadataTest < ActiveSupport::TestCase
  { "Rumble" => [ :scraped_html, "https://rumble.com" ],
    "Bitchute" => [ :scraped_html, "https://www.bitchute.com" ],
    "Odysee" => [ :hidden_rss, "https://odysee.com" ],
    "Peertube" => [ :scraped_html, "https://joinpeertube.org" ],
    "YoutubeRss" => [ :hidden_rss, "https://www.youtube.com" ],
    "YtDlp" => [ :official_api, "https://github.com/yt-dlp/yt-dlp" ] }.each do |name, (trust, homepage)|
    test "#{name} bridge has trust_level #{trust} and homepage #{homepage}" do
      bridge = "Bridges::#{name}".constantize
      assert_equal trust, bridge.trust_level
      assert_equal homepage, bridge.site_homepage
      assert_not_nil bridge.last_tested_against
      assert_not_nil bridge.author
    end
  end
end
