RedmineApp::Application.routes.draw do
  # App-level infrastructure routes (site favicon + health probe)
  get 'favicon.ico', to: proc { |_env|
    [301, { 'Location' => ActionController::Base.helpers.image_path('favicon.ico'), 'Content-Type' => 'text/html' }, []]
  }
  get 'health/services', to: proc { |_env|
    [200, { 'Content-Type' => 'application/json' }, ['{"status":"ok","services":["redmine"]}']]
  }
  post 'automyra_bridge/task/improve', to: 'automyra_bridge#improve_task', as: 'automyra_bridge_improve_task'
  post 'automyra_bridge/assistant_request', to: 'automyra_bridge#assistant_request', as: 'automyra_bridge_assistant_request'
  post 'automyra_bridge/webhooks/incoming', to: 'automyra_bridge_webhooks#incoming', as: 'automyra_bridge_incoming_webhook', defaults: { format: 'json' }
  get 'projects/:project_id/automyra_bridge', to: 'automyra_bridge_operator#index', as: 'automyra_bridge_operator'
  get 'projects/:project_id/automyra_bridge/diagnostics', to: 'automyra_bridge_operator#diagnostics', as: 'automyra_bridge_diagnostics'
  get 'automyra_bridge/diagnostics', to: 'automyra_bridge_operator#diagnostics', as: 'automyra_bridge_global_diagnostics'
  post 'projects/:project_id/automyra_bridge/jobs/:id/retry', to: 'automyra_bridge_operator#retry_job', as: 'automyra_bridge_retry_job'
  post 'projects/:project_id/automyra_bridge/jobs/:id/cancel', to: 'automyra_bridge_operator#cancel_job', as: 'automyra_bridge_cancel_job'
  post 'projects/:project_id/automyra_bridge/deliveries/:id/retry', to: 'automyra_bridge_operator#retry_delivery', as: 'automyra_bridge_retry_delivery'
  post 'projects/:project_id/automyra_bridge/deliveries/:id/cancel', to: 'automyra_bridge_operator#cancel_delivery', as: 'automyra_bridge_cancel_delivery'
  patch 'projects/:project_id/automyra_bridge/settings', to: 'automyra_bridge_operator#update_settings', as: 'automyra_bridge_project_settings'
  get 'automyra_bridge/proposals/:id', to: 'automyra_bridge_action_proposals#show', as: 'automyra_bridge_proposal'
  post 'automyra_bridge/proposals/:id/approve', to: 'automyra_bridge_action_proposals#approve', as: 'automyra_bridge_approve_proposal'
  post 'automyra_bridge/proposals/:id/reject', to: 'automyra_bridge_action_proposals#reject', as: 'automyra_bridge_reject_proposal'
  post 'automyra_bridge/chat/send', to: 'automyra_bridge_chat#send_message', as: 'automyra_bridge_chat_send'
  get  'automyra_bridge/chat/history', to: 'automyra_bridge_chat#history', as: 'automyra_bridge_chat_history'
  get  'automyra_bridge/chat/poll', to: 'automyra_bridge_chat#poll', as: 'automyra_bridge_chat_poll'
  get  'automyra_bridge/chat/runs/:id/events', to: 'automyra_bridge_chat#run_events', as: 'automyra_bridge_chat_run_events'
  get  'automyra_bridge/chat/runs/:id/events/stream', to: 'automyra_bridge_chat#run_events_stream', as: 'automyra_bridge_chat_run_events_stream'
  post 'automyra_bridge/chat/toggle_thread', to: 'automyra_bridge_chat#toggle_thread', as: 'automyra_bridge_chat_toggle_thread'
  post 'automyra_bridge/chat/mark_read', to: 'automyra_bridge_chat#mark_read', as: 'automyra_bridge_chat_mark_read'
  post 'automyra_bridge/chat/upload_attachment', to: 'automyra_bridge_chat#upload_attachment', as: 'automyra_bridge_chat_upload_attachment'
  post 'automyra_bridge/chat/retry_job', to: 'automyra_bridge_chat#retry_job', as: 'automyra_bridge_chat_retry_job'
  post 'automyra_bridge/chat/cancel_job', to: 'automyra_bridge_chat#cancel_job', as: 'automyra_bridge_chat_cancel_job'
  post 'automyra_bridge/chat/new_thread', to: 'automyra_bridge_chat#new_thread', as: 'automyra_bridge_chat_new_thread'

  get 'automyra/proposals', to: 'automyra_bridge_action_proposals#index', defaults: { format: 'json' }
  post 'automyra/proposals', to: 'automyra_bridge_action_proposals#create', defaults: { format: 'json' }
  get 'automyra/proposals/:id/status', to: 'automyra_bridge_action_proposals#status', defaults: { format: 'json' }
  post 'automyra/proposals/:id/status', to: 'automyra_bridge_action_proposals#status', defaults: { format: 'json' }
  post 'automyra/activity_log', to: 'automyra_bridge_activity_log#create', defaults: { format: 'json' }

  namespace :automyra_bridge do
    namespace :governance do
      resources :policies do
        collection do
          post :run_all_now
        end
        member do
          post :run_now
          post :toggle_enabled
        end
      end
      resources :runs, only: %i[index show]
      resources :findings, only: %i[index show]
      resources :actions, only: %i[index show]
    end
  end
end
