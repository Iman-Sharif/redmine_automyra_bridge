require 'digest'

module AutomyraBridge
  module Governance
    module Collectors
      class CandidateBatch
        attr_reader :candidates, :project_id, :scope

        def initialize(candidates:, project_id:, scope:)
          @candidates = Array(candidates)
          @project_id = project_id
          @scope = scope.to_s
        end

        def batch_id
          Digest::SHA256.hexdigest([scope, project_id, sorted_ids.join(',')].join(':'))
        end

        def count
          candidates.size
        end

        def metadata
          { batch_id: batch_id, count: count, project_id: project_id, scope: scope }
        end

        private

        def sorted_ids
          candidates.map { |candidate| candidate[:object_id] || candidate['object_id'] }.compact.map(&:to_i).sort
        end
      end
    end
  end
end
