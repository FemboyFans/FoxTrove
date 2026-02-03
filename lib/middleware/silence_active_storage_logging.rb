# frozen_string_literal: true

module Middleware
  class SilenceActiveStorageLogging
    def initialize(app)
      @app = app
    end

    def call(env)
      if env["PATH_INFO"].start_with?("/rails/active_storage")
        Rails.logger.silence do
          @app.call(env)
        end
      else
        @app.call(env)
      end
    end
  end
end
