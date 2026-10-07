require "net/http"
require "uri"

module JudgementDay
  # MT-Bench human judgments (lmsys/mt_bench_human_judgments, CC-BY-4.0):
  # expert pairwise votes on 80 questions. One row is one judge's vote on one
  # model pair, one question and one turn; several judges can share a pair.
  module Dataset
    ROWS_URL = "https://datasets-server.huggingface.co/rows".freeze
    DATASET = "lmsys/mt_bench_human_judgments".freeze
    PAGE = 100
    # Bumped when the item text changes, so cached judge responses and
    # reviews made on older items are never reused. v2 trims each
    # conversation to the turn the humans voted on.
    VERSION = "turn-trimmed@v2".freeze

    # MT-Bench numbers its 80 questions in blocks of 10 per category.
    CATEGORIES = %w[writing roleplay reasoning math coding extraction stem humanities].freeze

    module_function

    def raw_path
      JudgementDay.path("data", "raw", "mt_bench_human.jsonl")
    end

    def items_path
      JudgementDay.path("data", "items.jsonl")
    end

    def fetch(split: "human", http: Net::HTTP)
      rows = []
      offset = 0
      loop do
        uri = URI(ROWS_URL)
        uri.query = URI.encode_www_form(dataset: DATASET, config: "default", split: split, offset: offset, length: PAGE)
        res = http.get_response(uri)
        raise Error, "Dataset fetch failed (#{res.code}) at offset #{offset}" unless res.is_a?(Net::HTTPSuccess)
        page = JSON.parse(res.body)
        batch = page.fetch("rows").map { |r| r.fetch("row") }
        rows.concat(batch)
        offset += batch.size
        break if batch.empty? || offset >= page.fetch("num_rows_total")
      end
      JudgementDay.write_jsonl(raw_path, rows)
      rows
    end

    def category(question_id)
      CATEGORIES[(question_id.to_i - 81) / 10] || "other"
    end

    # The rows carry the full two-turn conversation even for turn-1 votes.
    # Keep only the turns up to the one the humans voted on.
    def trim(conversation, turn)
      Array(conversation).first(2 * turn.to_i)
    end

    def vote_for(row, model_a)
      winner = row.fetch("winner").to_s
      return "tie" if winner.start_with?("tie")
      picked = winner == "model_a" ? row["model_a"] : row["model_b"]
      picked == model_a ? "a" : "b"
    end

    # Groups votes by question, turn and model pair. Model A is always the
    # alphabetically first model so votes from either orientation line up.
    def build_items(rows, min_votes: 2)
      groups = rows.group_by { |r| [r["question_id"], r["turn"], [r["model_a"], r["model_b"]].sort] }
      items = groups.map do |(qid, turn, (a, b)), votes|
        first = votes.first
        conv_a = first["model_a"] == a ? first["conversation_a"] : first["conversation_b"]
        conv_b = first["model_a"] == a ? first["conversation_b"] : first["conversation_a"]
        tally = { "a" => 0, "b" => 0, "tie" => 0 }
        votes.each { |v| tally[vote_for(v, a)] += 1 }
        {
          "id" => "q#{qid}-t#{turn}-#{a}-vs-#{b}",
          "question_id" => qid, "turn" => turn, "category" => category(qid),
          "model_a" => a, "model_b" => b,
          "conversation_a" => trim(conv_a, turn), "conversation_b" => trim(conv_b, turn),
          "votes" => tally, "judges" => votes.map { |v| v["judge"] }
        }
      end
      items.select { |i| i["votes"].values.sum >= min_votes }.sort_by { |i| i["id"] }
    end

    # A stable, well-mixed sample: items ordered by hash, so the first 20 of
    # a smoke run are spread across questions and models.
    # `offset` skips items an earlier run already used, so a later run gets
    # fresh ones (the full run took the first 500).
    def sample(items, limit, offset: 0)
      shuffled = items.sort_by { |i| JudgementDay.unit_hash("sample:" + i["id"]) }.drop(offset)
      limit ? shuffled.first(limit) : shuffled
    end

    def load_items
      raise Error, "No items yet: run `bin/jd fetch` first" unless File.exist?(items_path)
      JudgementDay.read_jsonl(items_path).map do |i|
        i.merge("conversation_a" => trim(i["conversation_a"], i["turn"]),
                "conversation_b" => trim(i["conversation_b"], i["turn"]))
      end
    end
  end
end
