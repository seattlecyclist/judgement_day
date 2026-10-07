module JudgementDay
  # Claude reviews each confident disagreement between the judge and the human
  # majority. Reviews and Mike's spot-checks are appended to a committed,
  # append-only file so the history can be reviewed later.
  module Reviewer
    MODEL = "claude-opus-5-5".freeze
    PROMPT_VERSION = "disagreement-review@v1".freeze
    MAX_TOKENS = 4000
    LABELS = %w[judge_wrong humans_wrong question_unclear].freeze
    SPOTCHECK_SAMPLE = 20

    SYSTEM = <<~PROMPT.freeze
      You review disputed items from a study of AI assistant replies. Human expert raters compared two
      assistants' final replies to the same user, and an automated judge confidently disagreed with the
      human majority. Read both conversations and decide who is right.

      Labels:
      - judge_wrong: the human majority's choice is better supported.
      - humans_wrong: the judge's choice is better supported.
      - question_unclear: reasonable people could disagree, or the comparison can't be settled from the text.

      Check facts, math and code yourself rather than trusting either side. Reply with only a JSON object:
      {"label": "<one label>", "reason": "<two or three sentences>"}
    PROMPT

    module_function

    def path
      JudgementDay.path("reviews", "disagreements.jsonl")
    end

    def records
      JudgementDay.read_jsonl(path)
    end

    def review_id(item_id)
      Digest::SHA256.hexdigest("#{PROMPT_VERSION}:#{item_id}")[0, 12]
    end

    def name_for(label)
      { "a" => "Response A", "b" => "Response B", "tie" => "About the same" }.fetch(label)
    end

    def user_message(summary)
      item = summary["item"]
      p = summary["p"]
      <<~MSG
        ## Response A

        #{Judge.render_conversation(item['conversation_a'])}

        ## Response B

        #{Judge.render_conversation(item['conversation_b'])}

        ## The dispute

        Human votes: A #{item['votes']['a']}, B #{item['votes']['b']}, tie #{item['votes']['tie']}. Majority: #{name_for(summary['majority'])}.
        Judge: #{name_for(summary['pick'])} (A #{p['a'].round(2)}, B #{p['b'].round(2)}, tie #{p['tie'].round(2)}).
        Compare only the final assistant reply in each conversation.
      MSG
    end

    def parse(text)
      json = text[/\{.*\}/m] or return [nil, "unparseable reply: #{text[0, 200]}"]
      data = JSON.parse(json)
      label = data["label"].to_s
      LABELS.include?(label) ? [label, data["reason"].to_s] : [nil, "unknown label #{label}: #{data['reason']}"]
    rescue JSON::ParserError
      [nil, "unparseable reply: #{text[0, 200]}"]
    end

    def last_user_turn(conversation)
      Array(conversation).select { |t| t.is_a?(Hash) && t["role"].to_s == "user" }.last&.dig("content")
    end

    def last_assistant_turn(conversation)
      Array(conversation).reject { |t| t.is_a?(Hash) && t["role"].to_s == "user" }.last.then do |t|
        t.is_a?(Hash) ? t["content"] : t
      end
    end

    # Reviews confident disagreements not yet reviewed under this prompt.
    def review(run:, summaries:, threshold:, client:, budget:, limit: nil, log: $stdout)
      done = records.select { |r| r["record_type"] == "review" }.map { |r| r["review_id"] }.to_set
      todo = summaries.select { |s| s["majority"] && s["confidence"] >= threshold && !s["agrees"] }
                      .reject { |s| done.include?(review_id(s["item"]["id"])) }
      todo = todo.first(limit) if limit
      todo.each do |s|
        msg = user_message(s)
        budget.check!(:reviewer, input_chars: SYSTEM.bytesize + msg.bytesize, max_output_tokens: MAX_TOKENS)
        response = client.messages.create(
          model: MODEL.to_sym, max_tokens: MAX_TOKENS,
          output_config: { effort: :high },
          system_: SYSTEM, messages: [{ role: "user", content: msg }]
        )
        budget.record(:reviewer, input_tokens: response.usage.input_tokens, output_tokens: response.usage.output_tokens)
        text = response.content.select { |b| b.type == :text }.map(&:text).join
        label, reason = response.stop_reason == :refusal ? [nil, "reviewer declined"] : parse(text)
        item = s["item"]
        JudgementDay.append_jsonl(path, {
          "record_type" => "review", "review_id" => review_id(item["id"]), "run" => run,
          "item_id" => item["id"], "question_id" => item["question_id"], "turn" => item["turn"],
          "category" => item["category"], "model_a" => item["model_a"], "model_b" => item["model_b"],
          "user_prompt" => last_user_turn(item["conversation_a"]),
          "reply_a" => last_assistant_turn(item["conversation_a"]),
          "reply_b" => last_assistant_turn(item["conversation_b"]),
          "human_votes" => item["votes"], "human_majority" => s["majority"],
          "judge" => { "judge_version" => JUDGE_VERSION, "pick" => s["pick"],
                       "p" => s["p"].transform_values { |v| v.round(3) } },
          "reviewer" => { "model" => MODEL, "prompt_version" => PROMPT_VERSION, "effort" => "high" },
          "label" => label, "reason" => reason, "created_at" => Time.now.utc.iso8601
        })
        log.puts "#{item['id']}: #{label || 'needs a look'}"
      end
      log.puts format("Reviewed %d items, $%.4f spent", todo.size, budget.spent)
    rescue BudgetExceeded => e
      log.puts e.message
    end

    def reviews
      records.select { |r| r["record_type"] == "review" }
    end

    def spotchecks
      records.select { |r| r["record_type"] == "spotcheck" }
    end

    # Mike's spot-check sample: a stable 20 of the reviews, plus any review
    # Claude couldn't label. Lists the ones still waiting for a check.
    def pending_spotchecks
      checked = spotchecks.map { |r| r["review_id"] }.to_set
      all = reviews
      sample = all.sort_by { |r| JudgementDay.unit_hash("spot:" + r["review_id"]) }.first(SPOTCHECK_SAMPLE)
      sample |= all.select { |r| r["label"].nil? }
      sample.reject { |r| checked.include?(r["review_id"]) }
    end

    def add_spotcheck(review_id:, verdict:, note:, label: nil, by: "mike")
      raise Error, "Unknown review #{review_id}" unless reviews.any? { |r| r["review_id"] == review_id }
      raise Error, "Verdict must be agree or override" unless %w[agree override].include?(verdict)
      raise Error, "An override needs --label (#{LABELS.join(', ')})" if verdict == "override" && !LABELS.include?(label)
      JudgementDay.append_jsonl(path, {
        "record_type" => "spotcheck", "review_id" => review_id, "verdict" => verdict,
        "label" => verdict == "override" ? label : nil, "note" => note, "by" => by,
        "created_at" => Time.now.utc.iso8601
      })
    end
  end
end
