module JudgementDay
  # Scores items in each order and repeat. Every response is cached on disk by
  # rubric, item, order and repeat, so a rerun after a bug fix costs nothing.
  class Scorer
    PRESETS = {
      "smoke1" => { limit: 20, orders: 1, repeats: 1, cap: 1.0 },
      "smoke2" => { limit: 50, orders: 2, repeats: 1, cap: 1.0 },
      "full" => { limit: 500, orders: 2, repeats: 3, cap: 5.0 },
      # Every item the full run didn't use, scored once to test the locked setup.
      "confirm" => { offset: 500, limit: nil, orders: 2, repeats: 3, cap: 5.0 }
    }.freeze

    WORKERS = 8

    def initialize(client:, budget:, cache_dir: JudgementDay.path("data", "cache", "judge"), log: $stdout, workers: WORKERS)
      @client = client
      @budget = budget
      @cache_dir = File.join(cache_dir, Judge::RUBRIC_VERSION.tr("@", "_"), Dataset::VERSION.tr("@", "_"))
      @log = log
      @workers = [workers.to_i, 1].max
    end

    def cache_file(item, order, repeat)
      File.join(@cache_dir, "#{item['id']}-o#{order}-r#{repeat}.json")
    end

    # Runs the uncached calls on several threads. Rows come back in item,
    # order, repeat order whatever finishes first. If the cap would be
    # crossed, no new calls start and the finished ones are kept.
    def score(items, orders:, repeats:)
      jobs = items.flat_map { |item| (0...orders).flat_map { |o| (0...repeats).map { |r| [item, o, r] } } }
      responses = Array.new(jobs.size)
      cached = 0
      todo = []
      jobs.each_with_index do |(item, order, repeat), i|
        file = cache_file(item, order, repeat)
        if File.exist?(file)
          responses[i] = JSON.parse(File.read(file, encoding: "UTF-8"))
          cached += 1
        else
          todo << i
        end
      end

      queue = Queue.new
      todo.each { |i| queue << i }
      queue.close
      lock = Mutex.new
      calls = 0
      stop = nil
      errors = []
      threads = Array.new([@workers, todo.size].min) do
        Thread.new do
          while !stop && (i = queue.pop)
            item, order, repeat = jobs[i]
            body = Judge.request_body(item, order)
            begin
              reserved = @budget.reserve!(:judge, input_chars: JSON.generate(body).bytesize)
            rescue BudgetExceeded => e
              lock.synchronize { stop ||= e.message }
              break
            end
            begin
              res = @client.call(body)
            rescue StandardError => e
              @budget.settle(:judge, reserved)
              lock.synchronize { errors << e; stop ||= e.message }
              break
            end
            @budget.settle(:judge, reserved, input_tokens: res.dig("usage", "input_tokens").to_i,
                                             output_tokens: res.dig("usage", "output_tokens").to_i)
            file = cache_file(item, order, repeat)
            FileUtils.mkdir_p(File.dirname(file))
            File.write(file, JSON.pretty_generate(res))
            responses[i] = res
            lock.synchronize do
              calls += 1
              @log.puts format("  %d/%d new calls", calls, todo.size) if (calls % 250).zero?
            end
          end
        end
      end
      threads.each(&:join)

      @log.puts stop if stop
      @log.puts format("Scored %d items: %d new calls, %d cached, $%.4f spent", items.size, calls, cached, @budget.spent)
      raise errors.first if errors.any? && calls.zero? && cached.zero?
      jobs.each_with_index.filter_map do |(item, order, repeat), i|
        responses[i] && row(item, order, repeat, responses[i])
      end
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
