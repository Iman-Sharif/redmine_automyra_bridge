# frozen_string_literal: true

#
# Automyra creation-review webhook bridge (plugin-independent).
#
# WHY THIS FILE EXISTS (issue #423):
#   The redmine_automyra_bridge plugin that used to fire the
#   `redmica.issue_created` webhook on issue creation was disabled
#   (init.rb -> init.rb.f3disabled) and its hook/lib source files were
#   lost (gitignored, unrecoverable). As a result, issues created via the
#   REST API *and* the web UI no longer triggered the Hermes "creation
#   review" automation at all.
#
#   Redmica loads config/additional_environment.rb at boot via
#   instance_eval (see config/application.rb). Registering a model-level
#   `after_create_commit` callback here fires for EVERY creation path
#   (web UI, REST API, bulk import, copy, sub-task) with zero dependency
#   on the gutted plugin.
#
# DESIGN:
#   - after_create_commit (not after_create): the callback runs only AFTER
#     the DB transaction commits, so the issue is visible when the Hermes
#     skill reads it back via GET /issues/{id}.json (no read-before-commit
#     race).
#   - Delivery runs in a detached Thread doing a pure outbound HTTP POST
#     with primitive values extracted on the request thread (no
#     ActiveRecord access in the worker thread -> no connection-pool
#     checkout concern).
#   - Best-effort: every error is logged and swallowed so a webhook/
#     gateway problem can NEVER block or fail issue creation.
#   - The container reaches the host-side Hermes gateway through its
#     default-route gateway IP (the docker bridge), derived at runtime so
#     it survives container/bridge recreation. The public HTTPS URL is NOT
#     reachable from inside the container (no NAT hairpin).

require 'net/http'
require 'json'
require 'openssl'
require 'uri'

module AutomyraCreationReviewBridge
  WEBHOOK_ROUTE = 'redmica-creation-review'
  EVENT_TYPE    = 'redmica.issue_created'
  GATEWAY_PORT  = (ENV['HERMES_GATEWAY_PORT'] || '8644').to_i
  SECRET        = ENV['HERMES_CREATION_REVIEW_SECRET'] || 'maaE-RpKtwjU0te8whhbJ-K8Eoa-laerjf89YmA13e8'
  PUBLIC_BASE   = (ENV['REDMINE_PUBLIC_URL'] || 'https://redmica.bundecca.co.uk').chomp('/')
  TIMEOUT       = 10

  module_function

  # Derive the host (docker bridge) IP from the container's default
  # route (/proc/net/route, destination 0.0.0.0, little-endian hex).
  # Returns nil if it can't be determined.
  def gateway_host
    File.foreach('/proc/net/route') do |line|
      fields = line.split
      next unless fields.length > 2 && fields[1] == '00000000' # default route

      hex = fields[2]
      return [hex[6, 2], hex[4, 2], hex[2, 2], hex[0, 2]].map { |h| h.to_i(16) }.join('.')
    end
    nil
  rescue StandardError
    nil
  end

  def deliver(issue_id:, subject:, project_id:, project_name:, tracker_name:, author_name:, description:)
    host = gateway_host
    return if host.nil? || SECRET.to_s.empty?

    payload = {
      issue_id: issue_id,
      subject: subject,
      project_id: project_id,
      project_name: project_name,
      tracker_name: tracker_name,
      author_name: author_name,
      description: description,
      url: "#{PUBLIC_BASE}/issues/#{issue_id}"
    }
    body = { event_type: EVENT_TYPE, payload: payload }.to_json
    signature = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', SECRET, body)}"
    delivery_id = "issue-creation-#{issue_id}"

    uri = URI("http://#{host}:#{GATEWAY_PORT}/webhooks/#{WEBHOOK_ROUTE}")
    req = Net::HTTP::Post.new(uri.request_uri)
    req['Content-Type']        = 'application/json'
    req['X-Hub-Signature-256'] = signature
    req['X-GitHub-Event']      = EVENT_TYPE
    req['X-GitHub-Delivery']   = delivery_id
    req['User-Agent']          = 'Automyra-CreationReview-Bridge/1.0'
    req.body = body

    res = Net::HTTP.start(uri.hostname, uri.port, open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
      http.request(req)
    end

    if res.is_a?(Net::HTTPSuccess)
      Rails.logger.info("[AutomyraCreationReviewBridge] delivered #{delivery_id} event=#{EVENT_TYPE} status=#{res.code}")
    else
      Rails.logger.warn("[AutomyraCreationReviewBridge] non-success #{delivery_id} status=#{res.code} body=#{res.body.to_s[0, 200]}")
    end
  rescue StandardError => e
    Rails.logger.warn("[AutomyraCreationReviewBridge] delivery failed issue=#{issue_id} error=#{e.class}: #{e.message}")
  end
end

Rails.application.config.after_initialize do
  Issue.after_create_commit do |issue|
    # Extract primitives on the request thread (no AR access in the worker thread).
    issue_id     = issue.id
    subject      = issue.subject.to_s
    project_id   = issue.project&.identifier
    project_name = issue.project&.name
    tracker_name = issue.tracker&.name
    author_name  = issue.author&.name
    description  = issue.description.to_s

    Thread.new do
      AutomyraCreationReviewBridge.deliver(
        issue_id: issue_id, subject: subject, project_id: project_id,
        project_name: project_name, tracker_name: tracker_name,
        author_name: author_name, description: description
      )
    end
  rescue StandardError => e
    Rails.logger.warn("[AutomyraCreationReviewBridge] callback error issue=#{issue&.id} error=#{e.class}: #{e.message}")
  end

  Rails.logger.info('[AutomyraCreationReviewBridge] installed Issue.after_create_commit webhook hook')
end
