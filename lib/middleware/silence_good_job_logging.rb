# frozen_string_literal: true

module Middleware
  class SilenceGoodJobLogging
    def initialize(app)
      @app = app
    end

    def call(env)
      if env["PATH_INFO"].start_with?("/good_job")
        Rails.logger.silence do
          @app.call(env)
        end
      else
        @app.call(env)
      end
    end
  end
end
