module JudgementDay
  # A hard spend cap per run. Each call is priced before it is sent, using a
  # worst-case estimate; a call that could cross the cap is never made.
  # Actual spend from each response is appended to a local ledger.
  class Budget
    # USD per million tokens.
    PRICES = {
      judge: { input: 0.042, output: 0.0 },
      reviewer: { input: 4.00, output: 20.00 },
      # Not checked against a price list; set high on purpose so the cap
      # check stays safe and recorded spend errs high.
      reviewer_fable: { input: 15.00, output: 75.00 }
    }.freeze

    attr_reader :cap, :spent

    def initialize(cap:, run:, ledger: JudgementDay.path("data", "spend.jsonl"))
      @cap = cap.to_f
      @run = run
      @ledger = ledger
      @spent = 0.0
      @lock = Mutex.new
    end

    def self.cost(kind, input_tokens:, output_tokens: 0)
      p = PRICES.fetch(kind)
      (input_tokens * p[:input] + output_tokens * p[:output]) / 1_000_000.0
    end

    # Rough token count; deliberately high (3 characters per token).
    def self.estimate_tokens(text)
      (text.bytesize / 3.0).ceil
    end

    def check!(kind, input_chars:, max_output_tokens: 0)
      estimate = self.class.cost(kind, input_tokens: (input_chars / 3.0).ceil, output_tokens: max_output_tokens)
      return if @spent + estimate <= @cap
      raise BudgetExceeded, format("Stopping: next call could cost $%.4f and only $%.4f of the $%.2f cap is left",
                                   estimate, @cap - @spent, @cap)
    end

    # For concurrent callers: checks the cap and sets the worst-case estimate
    # aside in one step, so parallel calls can't jointly cross the cap.
    # Returns the reserved amount, to hand back to `settle`.
    def reserve!(kind, input_chars:, max_output_tokens: 0)
      @lock.synchronize do
        check!(kind, input_chars: input_chars, max_output_tokens: max_output_tokens)
        estimate = self.class.cost(kind, input_tokens: (input_chars / 3.0).ceil, output_tokens: max_output_tokens)
        @spent += estimate
        estimate
      end
    end

    # Releases a reservation and records the actual cost (nothing if the call failed).
    def settle(kind, reserved, input_tokens: nil, output_tokens: 0)
      @lock.synchronize do
        @spent -= reserved
        record(kind, input_tokens: input_tokens, output_tokens: output_tokens) if input_tokens
      end
    end

    def record(kind, input_tokens:, output_tokens: 0)
      cost = self.class.cost(kind, input_tokens: input_tokens, output_tokens: output_tokens)
      @spent += cost
      JudgementDay.append_jsonl(@ledger, { "at" => Time.now.utc.iso8601, "run" => @run, "kind" => kind.to_s,
                                           "input_tokens" => input_tokens, "output_tokens" => output_tokens,
                                           "cost_usd" => cost.round(6) })
      cost
    end

    def self.totals(ledger = JudgementDay.path("data", "spend.jsonl"))
      JudgementDay.read_jsonl(ledger).group_by { |r| [r["run"], r["kind"]] }
                  .transform_values { |rs| { calls: rs.size, cost_usd: rs.sum { |r| r["cost_usd"] }.round(4) } }
    end
  end
end
