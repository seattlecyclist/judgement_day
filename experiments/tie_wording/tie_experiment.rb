require_relative "../../lib/judgement_day"
require "json"
include JudgementDay

BASE_INSTRUCTIONS = Judge::QUESTION["instructions"]
TIE_RULE = " If neither reply is clearly better, because both are similarly good or similarly flawed, " \
           "answer that they are about equally helpful. Do not pick a side over small differences in length or style."
VARIANTS = {
  "pairwise-helpful@v2-tie-a" => BASE_INSTRUCTIONS + TIE_RULE,
  "pairwise-helpful@v2-tie-b" => BASE_INSTRUCTIONS + TIE_RULE + " Expert raters judge about one comparison in five a tie."
}.freeze

def swap(name, value)
  Judge.send(:remove_const, name)
  Judge.const_set(name, value)
end

def evaluate(items, rows)
  s = Metrics.per_item(items, rows).select { |x| x["majority"] }
  decided = s.select { |x| x["confidence"] >= 0.90 }
  ties = s.select { |x| x["majority"] == "tie" }
  {
    "items" => s.size, "agreement_all" => s.count { |x| x["agrees"] }.fdiv(s.size).round(3),
    "coverage@0.90" => decided.size.fdiv(s.size).round(3),
    "agreement@0.90" => decided.empty? ? nil : decided.count { |x| x["agrees"] }.fdiv(decided.size).round(3),
    "ties_caught" => "#{ties.count { |x| x['pick'] == 'tie' }}/#{ties.size}",
    "ties_called" => s.count { |x| x["pick"] == "tie" },
    "order_consistency" => Metrics.rate(s, "order_consistent", true)&.round(3),
    "avg_calibration_gap" => Metrics.calibration(s)["mean_gap"]
  }
end

items = Dataset.sample(Dataset.load_items, 500).reject { |i| Metrics.holdout?(i["id"]) }
ids = items.map { |i| i["id"] }.to_set
baseline = JudgementDay.read_jsonl(Report.scores_path("full")).select { |r| r["repeat"].zero? && ids.include?(r["item_id"]) }
results = { "baseline pairwise-helpful@v1" => evaluate(items, baseline) }
client = Judge::Client.new(api_key: Secrets.fetch(:judge))
VARIANTS.each do |version, instructions|
  swap(:RUBRIC_VERSION, version)
  swap(:QUESTION, Judge::QUESTION.merge("instructions" => instructions,
                                        "criteria" => Judge::QUESTION["criteria"].merge("tie" => "Neither final reply is clearly better; they are about equally helpful and accurate")))
  budget = Budget.new(cap: 1.0, run: "tie-#{version.split('-').last}")
  rows = Scorer.new(client: client, budget: budget).score(items, orders: 2, repeats: 1)
  JudgementDay.write_jsonl(File.join(__dir__, "scores_#{version.split("@").last}.jsonl"), rows)
  results[version] = evaluate(items, rows)
end
File.write(File.join(__dir__, "results.json"), JSON.pretty_generate(results))
results.each { |k, v| puts "#{k}: #{v}" }
