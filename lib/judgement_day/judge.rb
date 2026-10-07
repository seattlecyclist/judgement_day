require "net/http"
require "uri"

module JudgementDay
  # The AI judge: one Choice question per item, asked through the provider's
  # HTTP API. Outputs carry JUDGE_VERSION, never the provider or model name.
  module Judge
    ENDPOINT = "https://api.typesafe.ai/v1/systemone".freeze
    MODEL = "jev-1.13.0".freeze # pinned; never an alias that can move
    RUBRIC_VERSION = "pairwise-helpful@v1".freeze
    QUESTION_KEY = "which_better".freeze

    # Mirrors the question the human raters answered.
    QUESTION = {
      "type" => "choice",
      "instructions" => "Two AI assistants answered the same user. Compare only each assistant's final reply. " \
                        "Which reply is more helpful and accurate for the user?",
      "criteria" => {
        "response1" => "Response 1's final reply is more helpful and accurate",
        "response2" => "Response 2's final reply is more helpful and accurate",
        "tie" => "Both final replies are about equally helpful and accurate"
      }
    }.freeze

    module_function

    # Order 0 shows the item's base orientation; order 1 swaps it. The base
    # orientation is randomised per item so model A isn't always first.
    def first_shown(item, order)
      base = JudgementDay.unit_hash("orient:" + item["id"]) < 0.5 ? "a" : "b"
      order.zero? ? base : (base == "a" ? "b" : "a")
    end

    def render_conversation(conversation)
      Array(conversation).map do |turn|
        if turn.is_a?(Hash)
          role = turn["role"].to_s == "user" ? "User" : "Assistant"
          "#{role}: #{turn['content']}"
        else
          turn.to_s
        end
      end.join("\n\n")
    end

    def state(item, order)
      first = first_shown(item, order)
      second = first == "a" ? "b" : "a"
      <<~STATE
        ## Response 1

        #{render_conversation(item["conversation_#{first}"])}

        ## Response 2

        #{render_conversation(item["conversation_#{second}"])}
      STATE
    end

    def request_body(item, order)
      { "state" => state(item, order), "model" => MODEL, "questions" => { QUESTION_KEY => QUESTION } }
    end

    # Maps response1/response2 probabilities back to the item's A/B.
    def to_ab(item, order, probabilities)
      first = first_shown(item, order)
      p1 = probabilities.fetch("response1").to_f
      p2 = probabilities.fetch("response2").to_f
      a, b = first == "a" ? [p1, p2] : [p2, p1]
      { "a" => a, "b" => b, "tie" => probabilities.fetch("tie").to_f }
    end

    class Client
      RETRYABLE = [429, 500, 502, 503, 529].freeze

      def initialize(api_key:, max_retries: 5, sleeper: ->(s) { sleep(s) })
        @api_key = api_key
        @max_retries = max_retries
        @sleeper = sleeper
      end

      def call(body)
        uri = URI(ENDPOINT)
        attempt = 0
        loop do
          res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 120) do |http|
            req = Net::HTTP::Post.new(uri)
            req["Authorization"] = "Bearer #{@api_key}"
            req["Content-Type"] = "application/json"
            req.body = JSON.generate(body)
            http.request(req)
          end
          code = res.code.to_i
          return JSON.parse(res.body) if code == 200
          if RETRYABLE.include?(code) && attempt < @max_retries
            attempt += 1
            @sleeper.call(2**attempt)
            next
          end
          raise Error, "Judge API returned #{code}: #{res.body.to_s[0, 300]}"
        end
      end
    end
  end
end
