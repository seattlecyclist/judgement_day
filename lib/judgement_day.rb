require "json"
require "digest"
require "fileutils"
require "time"
require "set"

# Pilot pipeline: score human preference items with an AI judge, compare the
# judge to the human majority, and review the confident disagreements.
module JudgementDay
  class Error < StandardError; end
  class BudgetExceeded < Error; end

  ROOT = File.expand_path("..", __dir__)

  # Customer-facing label for the judge. The model behind it is internal.
  JUDGE_VERSION = "qpj-judge-2026.10".freeze

  def self.path(*parts)
    File.join(ROOT, *parts)
  end

  # Stable pseudo-random number in [0, 1) for a string, used for sampling,
  # display order and the holdout split so every run makes the same choices.
  def self.unit_hash(str)
    Digest::SHA256.hexdigest(str)[0, 8].to_i(16) / 2.0**32
  end

  def self.write_jsonl(file, rows)
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, rows.map { |r| JSON.generate(r) }.join("\n") + (rows.empty? ? "" : "\n"))
  end

  def self.read_jsonl(file)
    return [] unless File.exist?(file)
    File.readlines(file, chomp: true, encoding: "UTF-8").reject(&:empty?).map { |l| JSON.parse(l) }
  end

  def self.append_jsonl(file, row)
    FileUtils.mkdir_p(File.dirname(file))
    File.open(file, "a") { |f| f.puts(JSON.generate(row)) }
  end
end

require_relative "judgement_day/secrets"
require_relative "judgement_day/dataset"
require_relative "judgement_day/budget"
require_relative "judgement_day/judge"
require_relative "judgement_day/scorer"
require_relative "judgement_day/metrics"
require_relative "judgement_day/report"
require_relative "judgement_day/calibration"
require_relative "judgement_day/reviewer"
