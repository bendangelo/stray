ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"
require "vcr"
require "full_search/test_helpers"
require_relative "test_helpers/session_test_helper"

VCR.configure do |c|
  c.cassette_library_dir = "test/fixtures/vcr_cassettes"
  c.hook_into :webmock
  c.allow_http_connections_when_no_cassette = false
  c.default_cassette_options = {
    record: ENV["VCR_RECORD"] == "1" ? :all : :none,
    match_requests_on: [ :method, :uri ]
  }
end

WebMock.disable_net_connect!(allow_localhost: true)

module ActiveSupport
  class TestCase
    include FullSearch::TestHelpers

    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
