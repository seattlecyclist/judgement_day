require "open3"

module JudgementDay
  # API keys are read at run time and never written anywhere. An env var wins
  # if set; otherwise the key comes from a shell function in Mike's profile.
  module Secrets
    SOURCES = {
      judge: { env: "JD_JUDGE_API_KEY", function: "typesafe-key" },
      reviewer: { env: "ANTHROPIC_API_KEY", function: "anthropic-key" }
    }.freeze

    def self.fetch(name)
      source = SOURCES.fetch(name)
      from_env = ENV[source[:env]].to_s.strip
      return from_env unless from_env.empty?

      from_function(source[:function]) ||
        raise(Error, "No #{name} key: set #{source[:env]} or define the `#{source[:function]}` shell function")
    end

    # Shell functions only load in an interactive shell, so run one with -i
    # and take the last non-empty line of its output.
    def self.from_function(function)
      shell = ENV.fetch("SHELL", "/bin/zsh")
      out, status = Open3.capture2(shell, "-ic", function, err: File::NULL)
      return nil unless status.success?
      key = out.lines.map(&:strip).reject(&:empty?).last
      key unless key.nil? || key.empty?
    end
  end
end
