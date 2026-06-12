# frozen_string_literal: true

# ToolSnapshot — deterministic before/after tool-output diff harness (Task 11)
# =============================================================================
#
# PURPOSE
#   Pure-Ruby helper that captures the output of a defined set of Automyra
#   Bridge tools against FIXED inputs, normalizes the non-deterministic fields
#   (hash-based record IDs, timestamps, UUIDs), and emits a sorted-key, stable
#   JSON string. Two captures of unchanged code produce byte-identical JSON, so
#   any non-empty diff is a real behavior change — not noise from hash IDs.
#
#   This module does NOT boot Rails on its own. It is driven from inside the
#   already-booted test environment (see test/unit/tool_snapshot_test.rb), which
#   reuses the proven tool-invocation + fixture setup from Task 7
#   (test/unit/issue_task_pairs_characterization_test.rb).
#
# BEFORE / REFACTOR / AFTER WORKFLOW (for Tasks 13, 14, 15, 19)
#   The pure-refactor tasks must prove "zero behavior change", not merely
#   "tests still pass". Use this harness as that proof:
#
#     1. BEFORE  — on the current (green) code, capture the baseline:
#                    before = ToolSnapshot.normalize(ToolSnapshot.capture(inputs))
#                    File.write('/tmp/tool_snap_before.json', before)
#     2. REFACTOR — apply the refactor (extract mixin, remove swallow, etc.).
#     3. AFTER   — re-run the SAME capture on the refactored code:
#                    after = ToolSnapshot.normalize(ToolSnapshot.capture(inputs))
#                    File.write('/tmp/tool_snap_after.json', after)
#     4. ASSERT  — diff must be EMPTY:
#                    assert_equal before, after   # (or `diff` the two files)
#
#   A non-empty diff names the exact tool + field that changed, so a refactor
#   that accidentally alters a return shape is caught immediately.
#
# INPUT CONTRACT
#   ToolSnapshot.capture(tools_and_inputs)
#     tools_and_inputs : Array of [label, tool, job, user, input]
#       label : String snapshot key (e.g. 'issue.add_comment')
#       tool  : object responding to #call(job, user, input)
#       job   : AutomyraBridgeJob (source-resolving context)
#       user  : User
#       input : Hash params passed to the tool
#     returns : normalized Hash { label => {ok:, result:|error_class:,error_message:} }
#
#   ToolSnapshot.normalize(obj)
#     returns : stable JSON String (recursively scrubbed + sorted keys).
#
# NORMALIZATION RULES
#   * Hash keys named `id` or ending in `_id`        -> "<ID>"
#   * Hash keys ending in `_at` or `_on`             -> "<TS>"
#   * String values matching a UUID                  -> "<UUID>"
#   * String values matching an ISO-8601 datetime    -> "<TS>"
#   * All hash keys are recursively sorted; output is pretty JSON for readable
#     diffs. Plain date strings (e.g. "2026-06-12") are KEPT — they are stable
#     within a single capture run and carry meaning.
module ToolSnapshot
  module_function

  UUID_RE = /\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/
  ISO_TS_RE = /\A\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}/
  ID_KEY_RE = /\A(id|.*_id)\z/
  TS_KEY_RE = /(_at|_on)\z/

  def capture(tools_and_inputs)
    snapshot = {}
    tools_and_inputs.each do |label, tool, job, user, input|
      snapshot[label.to_s] = invoke(tool, job, user, input)
    end
    scrub(snapshot)
  end

  def invoke(tool, job, user, input)
    result = tool.call(job, user, input)
    { 'ok' => true, 'result' => result }
  rescue StandardError => e
    { 'ok' => false, 'error_class' => e.class.name, 'error_message' => e.message }
  end

  def normalize(obj)
    stable_json(scrub(obj))
  end

  def scrub(obj, key = nil)
    case obj
    when Hash
      obj.each_with_object({}) { |(k, v), acc| acc[k.to_s] = scrub(v, k.to_s) }
    when Array
      obj.map { |v| scrub(v, key) }
    else
      scrub_scalar(obj, key)
    end
  end

  def scrub_scalar(value, key)
    k = key.to_s
    return '<ID>' if ID_KEY_RE.match?(k)
    return '<TS>' if TS_KEY_RE.match?(k)

    if value.is_a?(String)
      return '<UUID>' if UUID_RE.match?(value)
      return '<TS>' if ISO_TS_RE.match?(value)
    end
    value
  end

  def stable_json(obj)
    JSON.pretty_generate(deep_sort(obj))
  end

  def deep_sort(obj)
    case obj
    when Hash
      obj.sort_by { |k, _| k.to_s }.each_with_object({}) do |(k, v), acc|
        acc[k.to_s] = deep_sort(v)
      end
    when Array
      obj.map { |v| deep_sort(v) }
    else
      obj
    end
  end
end
