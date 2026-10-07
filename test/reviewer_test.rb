require "test_helper"

class ReviewerTest < Minitest::Test
  R = JudgementDay::Reviewer

  FakeBlock = Struct.new(:type, :text)
  FakeUsage = Struct.new(:input_tokens, :output_tokens)
  FakeMessage = Struct.new(:content, :usage, :stop_reason)

  class FakeClaude
    attr_reader :requests

    def initialize(text)
      @text = text
      @requests = []
    end

    def messages
      self
    end

    def create(**kwargs)
      @requests << kwargs
      FakeMessage.new([FakeBlock.new(:text, @text)], FakeUsage.new(2000, 300), :end_turn)
    end
  end

  def setup
    @dir = Dir.mktmpdir
    @path = File.join(@dir, "disagreements.jsonl")
    R.singleton_class.alias_method(:orig_path, :path)
    path = @path
    R.define_singleton_method(:path) { path }
  end

  def teardown
    R.singleton_class.alias_method(:path, :orig_path)
    FileUtils.rm_rf(@dir)
  end

  def summary
    item = JudgementDay::Dataset.build_items(Fixtures.rows, min_votes: 2).first
    { "item" => item, "majority" => "b", "pick" => "a", "agrees" => false, "confidence" => 0.9,
      "p" => { "a" => 0.9, "b" => 0.05, "tie" => 0.05 } }
  end

  def budget
    JudgementDay::Budget.new(cap: 10, run: "t", ledger: File.join(@dir, "spend.jsonl"))
  end

  def test_parse
    assert_equal ["humans_wrong", "ok"], R.parse(%({"label":"humans_wrong","reason":"ok"}))
    assert_nil R.parse("nope").first
  end

  def test_review_appends_once_and_spotchecks_append
    claude = FakeClaude.new(%({"label":"judge_wrong","reason":"Humans were right."}))
    R.review(run: "t", summaries: [summary], threshold: 0.8, client: claude, budget: budget, log: StringIO.new)
    R.review(run: "t", summaries: [summary], threshold: 0.8, client: claude, budget: budget, log: StringIO.new)
    assert_equal 1, claude.requests.size
    assert_equal :"claude-opus-5-5", claude.requests.first[:model]
    review = R.reviews.first
    assert_equal "judge_wrong", review["label"]
    assert_equal 1, R.pending_spotchecks.size

    R.add_spotcheck(review_id: review["review_id"], verdict: "agree", note: "Fine")
    assert_empty R.pending_spotchecks
    assert_equal 2, File.readlines(@path).size
    assert_raises(JudgementDay::Error) { R.add_spotcheck(review_id: review["review_id"], verdict: "override", note: "x") }
  end
end
