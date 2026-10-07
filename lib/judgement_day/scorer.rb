module JudgementDay
  # Scores items in each order and repeat. Every response is cached on disk by
  # rubric, item, order and repeat, so a rerun after a bug fix costs nothing.
  class Scorer
    PRESETS = {
      "smoke1" => { limit: 20, orders: 1, repeats: 1, cap: 1.0 },
      "smoke2" => { limit: 50, orders: 2, repeats: 1, cap: 1.0 },
      "full" => { limit: 500, orders: 2, repeats: 3, cap: 5.0 }
    }.freeze

    def initialize(client:, budget:, cache_dir: JudgementDay.path("data", "cache", "judge"), log: $stdout)
      @client = client
      @budget = budget
      @cache_dir = File.join(cache_dir, Judge::RUBRIC_VERSION.tr("@", "_"))
      @log = log
    end

    def cache_file(item, order, repeat)
      File.join(@cache_dir, "#{item['id']}-o#{order}-r#{repeat}.json")
    end

    def score(items, orders:, repeats:)
      rows = []
      calls = cached = 0
      items.each do |item|
        orders.times do |order|
          repeats.times do |repeat|
            file = cache_file(item, order, repeat)
            response =
              if File.exist?(file)
                cached += 1
                JSON.parse(File.read(file, encoding: "UTF-8"))
              else
                body = Judge.request_body(item, order)
                @budget.check!(:judge, input_chars: JSON.generate(body).bytesize)
                res = @client.call(body)
                @budget.record(:judge, input_tokens: res.dig("usage", "input_tokens").to_i,
                                       output_tokens: res.dig("usage", "output_tokens").to_i)
                FileUtils.mkdir_p(File.dirname(file))
                File.write(file, JSON.pretty_generate(res))
                calls += 1
                res
              end
            rows << row(item, order, repeat, response)
          end
        end
      end
      @log.puts format("Scored %d items: %d new calls, %d cached, $%.4f spent", items.size, calls, cached, @budget.spent)
      rows
    rescue BudgetExceeded => e
      @log.puts e.message
      rows
    end

    def row(item, order, repeat, response)
      answer = response.fetch("answers").fetch(Judge::QUESTION_KEY)
      {
        "item_id" => item["id"], "order" => order, "repeat" => repeat,
        "first_shown" => Judge.first_shown(item, order),
        "p" => Judge.to_ab(item, order, answer.fetch("probabilities")),
        "confidence" => answer["confidence"],
        "model" => response["model"], "usage" => response["usage"]
      }
    end
  end
end
