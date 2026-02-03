# frozen_string_literal: true

module Middleware
  class SilenceStatsLogging
    def initialize(app)
      @app = app
    end

    def call(env)
      if %w[/stats.json /stats/selenium].include?(env["PATH_INFO"])
        Rails.logger.silence do
          @app.call(env)
        end
      else
        @app.call(env)
      end
    end
  end
end
