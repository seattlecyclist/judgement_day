require_relative "../../lib/judgement_day"
require "anthropic"
require "json"

MODEL = "claude-fable-5-1"
MAX_TOKENS = 8000
OUT = JudgementDay.path("reviews", "fable_second_opinion.jsonl")
SYSTEM = JudgementDay::Reviewer::SYSTEM.sub(
  '{"label": "<one label>", "reason": "<two or three sentences>"}',
  '{"label": "<one label>", "reason": "<two or three sentences>", "plain": "<two or three sentences for a non-expert: what the question asks and what separates the two replies>"}'
)

class FableBudget < JudgementDay::Budget
  def self.cost(_kind, input_tokens:, output_tokens: 0)
    (input_tokens * 10.0 + output_tokens * 50.0) / 1_000_000.0
  end
end

items = JudgementDay::Dataset.load_items.to_h { |i| [i["id"], i] }
done = JudgementDay.read_jsonl(OUT).map { |r| r["review_id"] }
reviews = JudgementDay::Reviewer.reviews.select { |r| JudgementDay::Reviewer.data_version(r) == JudgementDay::Dataset::VERSION && r.dig("reviewer", "model") == JudgementDay::Reviewer::MODEL }.reject { |r| done.include?(r["review_id"]) }
budget = FableBudget.new(cap: 5.0, run: "fable-check-v2")
client = Anthropic::Client.new(api_key: JudgementDay::Secrets.fetch(:reviewer))

reviews.each do |r|
  item = items.fetch(r["item_id"])
  keep = item["turn"] * 2
  trimmed = item.merge("conversation_a" => item["conversation_a"].first(keep), "conversation_b" => item["conversation_b"].first(keep))
  msg = JudgementDay::Reviewer.user_message({ "item" => trimmed, "p" => r["judge"]["p"], "pick" => r["judge"]["pick"], "majority" => r["human_majority"] })
  budget.check!(:reviewer, input_chars: SYSTEM.bytesize + msg.bytesize, max_output_tokens: MAX_TOKENS)
  response = client.messages.create(model: MODEL.to_sym, max_tokens: MAX_TOKENS, output_config: { effort: :medium },
                                    system_: SYSTEM, messages: [{ role: "user", content: msg }])
  budget.record(:reviewer, input_tokens: response.usage.input_tokens, output_tokens: response.usage.output_tokens)
  text = response.content.select { |b| b.type == :text }.map(&:text).join
  data = begin
    response.stop_reason == :refusal ? { "label" => nil, "reason" => "declined" } : JSON.parse(text[/\{.*\}/m])
  rescue StandardError
    { "label" => nil, "reason" => "unparseable: #{text[0, 200]}" }
  end
  JudgementDay.append_jsonl(OUT, { "review_id" => r["review_id"], "item_id" => r["item_id"], "turn" => item["turn"],
                                   "model" => MODEL, "effort" => "medium", "stop_reason" => response.stop_reason.to_s,
                                   "label" => data["label"], "reason" => data["reason"], "plain" => data["plain"],
                                   "opus_label" => r["label"], "created_at" => Time.now.utc.iso8601 })
  puts "#{r['item_id']} (turn #{item['turn']}): fable #{data['label'] || 'none'} | opus #{r['label']}"
end
puts format("Done, $%.4f spent", budget.spent)
