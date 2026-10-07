require_relative "../../lib/judgement_day"
require "json"
items = JudgementDay::Dataset.load_items.to_h { |i| [i["id"], i] }
fable = JudgementDay.read_jsonl(JudgementDay.path("reviews", "fable_second_opinion.jsonl")).to_h { |f| [f["review_id"], f.slice("label", "reason", "plain")] }
pending = JudgementDay::Reviewer.pending_spotchecks
labels = { "user" => "User", "assistant" => "Assistant" }
data = pending.map do |r|
  it = items.fetch(r["item_id"])
  ca, cb = it["conversation_a"], it["conversation_b"]
  context = ca[0...-2].each_with_index.flat_map do |m, k|
    next [{ "label" => "User, turn #{k / 2 + 1}", "content" => m["content"] }] if m["role"] == "user"
    [{ "label" => "Response A, turn #{k / 2 + 1}", "content" => m["content"] },
     { "label" => "Response B, turn #{k / 2 + 1}", "content" => cb[k]["content"] }]
  end
  { "fable" => fable[r["review_id"]] }.merge(r.slice("review_id", "item_id", "category", "turn", "model_a", "model_b", "human_votes", "human_majority", "judge", "reviewer", "label", "reason"))
    .merge("wrong_turn" => false, "user_prompt" => ca[-2]["content"], "reply_a" => ca[-1]["content"], "reply_b" => cb[-1]["content"], "context" => context)
end
data = data.each_with_index.sort_by { |d, k| [d["fable"] && d["fable"]["label"] == d["label"] ? 1 : 0, k] }.map(&:first)
html = File.read(File.join(__dir__, "spotcheck_template.html"), encoding: "UTF-8")
FileUtils.mkdir_p(JudgementDay.path("tmp")); File.write(JudgementDay.path("tmp", "spotcheck.html"), html.sub("__DATA__") { JSON.generate(data).gsub("</", "<\\/") })
puts "#{data.size} reviews, #{data.count { |d| d['fable'] }} with a Fable second opinion, #{data.count { |d| d['context'].any? }} with earlier-turn context"
