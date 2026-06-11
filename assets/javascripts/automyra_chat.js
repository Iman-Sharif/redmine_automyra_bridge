(function() {
  'use strict';

  // Manual QA checklist for live chat updates:
  // - Open the panel and confirm it refreshes from /automyra_bridge/chat/history before polling.
  // - Send a message and confirm the temporary local user bubble reconciles with the server message.
  // - Confirm polling includes last_seen_update_at and pending assistant messages morph to delivered/failed.
  // - Toggle page/global threads, retry a failed response, and verify visible messages reconcile without hard refresh.

  var AutomyraChat = {
    panelOpen: false,
    pollInterval: null,
    eventSource: null,
    activeRunId: null,
    lastRunEventId: 0,
    sseFallbackActive: false,
    lastMessageId: 0,
    lastSeenUpdateAt: '',
    threadKind: 'page',
    isLoading: false,

    init: function() {
      this.detectThreadKind();
      this.detectLastMessageId();
      this.bindEvents();
      this.restorePanelState();
      this.startPolling();
    },

    bindEvents: function() {
      var button = document.querySelector('[data-automyra-chat="floating-button"]');
      if (button) {
        button.addEventListener('click', this.togglePanel.bind(this));
      }

      var closeBtn = document.querySelector('[data-automyra-chat="close-panel"]');
      if (closeBtn) {
        closeBtn.addEventListener('click', this.closePanel.bind(this));
      }

      document.addEventListener('keydown', function(event) {
        if (event.key === 'Escape' && this.panelOpen) {
          this.closePanel();
        }
      }.bind(this));

      var sendBtn = document.querySelector('[data-automyra-chat="send-btn"]');
      if (sendBtn) {
        sendBtn.addEventListener('click', this.sendMessage.bind(this));
      }

      var textarea = document.querySelector('[data-automyra-chat="input"]');
      if (textarea) {
        textarea.addEventListener('keydown', function(event) {
          if (event.key === 'Enter' && !event.shiftKey) {
            event.preventDefault();
            this.sendMessage();
          }
        }.bind(this));
      }

      var markReadBtn = document.querySelector('[data-automyra-chat="mark-read"]');
      if (markReadBtn) {
        markReadBtn.addEventListener('click', this.markRead.bind(this));
      }

      var toggleBtn = document.querySelector('[data-automyra-chat="toggle-thread"]');
      if (toggleBtn) {
        toggleBtn.addEventListener('click', this.toggleThread.bind(this));
      }

      var newThreadBtn = document.querySelector('[data-automyra-chat="new-thread"]');
      if (newThreadBtn) {
        newThreadBtn.addEventListener('click', this.newThread.bind(this));
      }

      var fileInput = document.querySelector('[data-automyra-chat="file-input"]');
      if (fileInput) {
        fileInput.addEventListener('change', this.sendAttachment.bind(this));
      }

      var attachmentBtn = document.querySelector('[data-automyra-chat="attachment-btn"], [data-automyra-chat="attach-btn"]');
      if (attachmentBtn) {
        attachmentBtn.addEventListener('click', this.triggerFileInput.bind(this));
      }

      document.addEventListener('click', function(event) {
        var actionButton = event.target.closest('[data-proposal-action="approve"], [data-proposal-action="reject"]');
        if (actionButton) {
          event.preventDefault();
          this.handleProposalAction(actionButton);
        }
      }.bind(this));

      document.addEventListener('click', function(event) {
        var retryBtn = event.target.closest('[data-chat-retry-job]');
        if (retryBtn) {
          event.preventDefault();
          this.retryJob(retryBtn.getAttribute('data-chat-retry-job'));
        }

        var cancelBtn = event.target.closest('[data-chat-cancel-job]');
        if (cancelBtn) {
          event.preventDefault();
          this.cancelJob(cancelBtn.getAttribute('data-chat-cancel-job'));
        }
      }.bind(this));
    },

    togglePanel: function() {
      this.panelOpen = !this.panelOpen;
      this.applyPanelState();
      this.savePanelState();

      if (this.panelOpen) {
        try {
          window.sessionStorage.setItem('automyraChatOpenedOnce', 'true');
          window.sessionStorage.removeItem('automyra_chat_user_closed');
        } catch (error) {
          console.warn('Automyra chat storage error:', error);
        }
        this.refreshHistory().then(function() {
          this.scrollToBottom();
          this.markRead();
          this.startPolling();
          this.pollForUpdates();
        }.bind(this));
      }
    },

    closePanel: function() {
      this.panelOpen = false;
      this.closeEventSource();
      this.stopPolling();
      this.applyPanelState();
      this.savePanelState();
      try {
        window.sessionStorage.setItem('automyra_chat_user_closed', 'true');
      } catch (error) {
        console.warn('Automyra chat storage error:', error);
      }
    },

    applyPanelState: function() {
      var panel = document.getElementById('automyra-chat-panel');
      if (panel) {
        panel.classList.toggle('automyra-chat-hidden', !this.panelOpen);
      }
    },

    savePanelState: function() {
      try {
        window.localStorage.setItem('automyra_chat_panel_open', this.panelOpen ? 'true' : 'false');
      } catch (error) {
        console.warn('Automyra chat storage error:', error);
      }
    },

    restorePanelState: function() {
      var open = false;
      try {
        open = window.localStorage.getItem('automyra_chat_panel_open') === 'true';
      } catch (error) {
        open = false;
      }

      var panel = document.getElementById('automyra-chat-panel');
      var unreadCount = panel ? parseInt(panel.getAttribute('data-unread-count') || '0', 10) : 0;
      var userClosed = false;
      var openedOnce = false;
      try {
        userClosed = window.sessionStorage.getItem('automyra_chat_user_closed') === 'true';
        openedOnce = window.sessionStorage.getItem('automyraChatOpenedOnce') === 'true';
      } catch (error) {
        console.warn('Automyra chat storage error:', error);
      }

      if (unreadCount > 0 && openedOnce && !userClosed) {
        this.panelOpen = true;
        this.applyPanelState();
        this.refreshHistory().then(function() {
          this.scrollToBottom();
          this.markRead();
          this.startPolling();
        }.bind(this));
      } else if (open) {
        this.panelOpen = true;
        this.applyPanelState();
        this.refreshHistory().then(function() {
          this.scrollToBottom();
          this.startPolling();
        }.bind(this));
      }
    },

    sendMessage: function() {
      if (this.isLoading) return;

      var textarea = document.querySelector('[data-automyra-chat="input"]');
      if (!textarea || !textarea.value.trim()) return;

      var content = textarea.value.trim();
      var pageContext = this.getPageContext();

      this.appendUserMessage(content);
      this.setLoading(true);
      this.showStatus('Automyra is thinking...');
      textarea.value = '';
      this.scrollToBottom();

      fetch('/automyra_bridge/chat/send', {
        method: 'POST',
        credentials: 'same-origin',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.csrfToken(),
          'Accept': 'application/json'
        },
        body: JSON.stringify({
          content: content,
          page_type: pageContext.page_type,
          page_id: pageContext.page_id,
          project_id: pageContext.project_id,
          url_path: pageContext.url_path,
          page_title: pageContext.page_title,
          thread_kind: this.threadKind
        })
      })
      .then(function(response) {
        if (!response.ok) throw new Error('Send failed: ' + response.status);
        if (response.status === 204) return {};
        return response.json();
      })
      .then(function(data) {
        this.setLoading(false);
        this.updateThreadState(data);
        this.reconcileTempUserMessage(content, data.message || data.user_message);
        this.renderMessages(this.responseMessages(data));
        this.updateCursors(data);
        if (data.job) {
          this.showStatus(this.jobStatusText(data.job));
        } else {
          this.hideStatus();
        }
        if (data.run_id) {
          this.subscribeToRunEvents(data.run_id);
        }
        this.pollForUpdates();
      }.bind(this))
      .catch(function(error) {
        this.setLoading(false);
        this.hideStatus();
        this.appendSystemMessage('Error: ' + error.message);
        this.scrollToBottom();
      }.bind(this));
    },

    sendAttachment: function() {
      var fileInput = document.querySelector('[data-automyra-chat="file-input"]');
      if (!fileInput || !fileInput.files || fileInput.files.length === 0) return;

      var file = fileInput.files[0];
      var thread = this.currentThread() || {};
      var formData = new FormData();
      formData.append('file', file);
      formData.append('thread_id', thread.id || '');
      formData.append('thread_kind', thread.kind || this.threadKind);

      this.showStatus('Uploading attachment...');

      fetch('/automyra_bridge/chat/upload_attachment', {
        method: 'POST',
        credentials: 'same-origin',
        headers: {
          'X-CSRF-Token': this.csrfToken(),
          'Accept': 'application/json'
        },
        body: formData
      })
      .then(function(response) {
        if (!response.ok) throw new Error('Upload failed: ' + response.status);
        if (response.status === 204) return {};
        return response.json();
      })
      .then(function(data) {
        var filename = (data.attachment && data.attachment.filename) || file.name;
        this.hideStatus();
        this.appendSystemMessage('Uploaded attachment: ' + filename);
        fileInput.value = '';
        this.scrollToBottom();
        this.pollForUpdates();
      }.bind(this))
      .catch(function(error) {
        this.hideStatus();
        this.appendSystemMessage('Error: ' + error.message);
        fileInput.value = '';
        this.scrollToBottom();
      }.bind(this));
    },

    triggerFileInput: function() {
      var fileInput = document.querySelector('[data-automyra-chat="file-input"]');
      if (fileInput) {
        fileInput.click();
      }
    },

    pollForUpdates: function() {
      if (!this.panelOpen) return;

      var thread = this.currentThread();
      var params = ['last_message_id=' + encodeURIComponent(this.lastMessageId || 0)];
      params.push('last_seen_update_at=' + encodeURIComponent(this.lastSeenUpdateAt || ''));
      if (thread && thread.id) params.push('thread_id=' + encodeURIComponent(thread.id));
      if (thread && thread.kind) params.push('thread_kind=' + encodeURIComponent(thread.kind));

      fetch('/automyra_bridge/chat/poll?' + params.join('&'), {
        credentials: 'same-origin',
        headers: {
          'X-CSRF-Token': this.csrfToken(),
          'Accept': 'application/json'
        }
      })
      .then(function(response) {
        if (!response.ok) throw new Error('Poll failed: ' + response.status);
        return response.json();
      })
      .then(function(data) {
        if (data.messages && data.messages.length > 0) {
          this.renderMessages(data.messages);
        }
        this.updateCursors(data);
        this.updateUnreadBadge(data.unread_count || 0);
        this.updatePendingJobStatus();
      }.bind(this))
      .catch(function() {
        console.warn('Automyra chat poll failed');
        this.refreshHistory();
      });
    },

    startPolling: function() {
      this.stopPolling();
      if (!this.panelOpen) return;

      this.pollInterval = window.setInterval(function() {
        if (document.visibilityState === 'visible' && this.panelOpen === true) {
          this.pollForUpdates();
        }
      }.bind(this), 5000);
    },

    stopPolling: function() {
      if (this.pollInterval) {
        window.clearInterval(this.pollInterval);
        this.pollInterval = null;
      }
    },

    sseEnabled: function() {
      return !!(window.automyraSettings && window.automyraSettings.enable_sse && window.EventSource);
    },

    subscribeToRunEvents: function(runId) {
      if (!this.panelOpen || !runId) return;
      this.closeEventSource();

      this.activeRunId = runId;
      this.lastRunEventId = 0;
      this.sseFallbackActive = false;
      this.hideLiveFallbackNotice();

      if (!this.sseEnabled()) {
        this.startPolling();
        return;
      }

      this.stopPolling();
      var url = '/automyra_bridge/chat/runs/' + encodeURIComponent(runId) + '/events/stream';
      this.eventSource = new window.EventSource(url, { withCredentials: true });

      this.eventSource.onmessage = function(event) {
        this.handleRunEvent(event);
      }.bind(this);

      this.eventSource.addEventListener('error', function() {
        this.fallbackToPolling();
      }.bind(this));

      this.eventSource.onerror = function() {
        this.fallbackToPolling();
      }.bind(this);
    },

    handleRunEvent: function(event) {
      var data = {};
      try {
        data = JSON.parse(event.data || '{}');
      } catch (error) {
        console.warn('Automyra SSE event parse failed:', error);
      }

      if (data.id) this.lastRunEventId = data.id;
      this.renderRunEvent(data);
      this.pollForUpdates();

      if (this.runEventTerminal(data)) {
        this.closeEventSource();
        this.pollForUpdates();
      }
    },

    runEventTerminal: function(data) {
      if (!data) return false;
      if (data.status && ['completed', 'failed', 'cancelled'].indexOf(String(data.status)) !== -1) return true;
      return ['run.completed', 'run.failed', 'run.cancelled'].indexOf(String(data.event_type)) !== -1;
    },

    fallbackToPolling: function() {
      if (this.sseFallbackActive) return;
      this.sseFallbackActive = true;
      this.closeEventSource();
      this.showLiveFallbackNotice();
      this.startPolling();
      this.pollForUpdates();
    },

    closeEventSource: function() {
      if (this.eventSource) {
        this.eventSource.close();
        this.eventSource = null;
      }
      this.activeRunId = null;
    },

    fetchRunEvents: function(runId) {
      if (!runId) return;

      var url = '/automyra_bridge/chat/runs/' + encodeURIComponent(runId) + '/events';
      if (this.lastRunEventId) url += '?after_id=' + encodeURIComponent(this.lastRunEventId);

      fetch(url, {
        credentials: 'same-origin',
        headers: {
          'X-CSRF-Token': this.csrfToken(),
          'Accept': 'application/json'
        }
      })
      .then(function(response) {
        if (!response.ok) throw new Error('Run event refresh failed: ' + response.status);
        return response.json();
      })
      .then(function(data) {
        (data.events || []).forEach(function(runEvent) {
          if (runEvent.id) this.lastRunEventId = runEvent.id;
          this.renderRunEvent(runEvent);
        }.bind(this));
        if (data.run_status) this.showStatus(this.titleize(data.run_status));
      }.bind(this))
      .catch(function() {
        console.warn('Automyra run event refresh failed');
      });
    },

    showLiveFallbackNotice: function() {
      var status = this.statusElement();
      if (!status) return;
      status.textContent = 'Live stream unavailable; using polling.';
      status.classList.remove('automyra-chat-hidden');
      status.classList.add('automyra-chat-status--notice');
    },

    hideLiveFallbackNotice: function() {
      var status = this.statusElement();
      if (!status) return;
      if (status.textContent === 'Live stream unavailable; using polling.') {
        status.classList.add('automyra-chat-hidden');
      }
      status.classList.remove('automyra-chat-status--notice');
    },

    renderMessages: function(messages) {
      var list = document.querySelector('[data-automyra-chat="message-list"]');
      if (!list) return;
      var shouldScroll = this.isNearBottom(list);

      messages.forEach(function(msg) {
        if (!msg || !msg.id) return;

        var div = list.querySelector('[data-message-id="' + this.escapeSelectorValue(msg.id) + '"]');
        if (!div) {
          div = document.createElement('div');
          div.setAttribute('data-message-id', msg.id);
          list.appendChild(div);
        }
        div.className = 'automyra-chat-message automyra-chat-message--' + this.escapeAttribute(msg.role || 'system');
        div.setAttribute('data-message-status', msg.status || 'delivered');
        if (msg.updated_at) div.setAttribute('data-message-updated-at', msg.updated_at);
        if (msg.job_id) div.setAttribute('data-message-job-id', msg.job_id);
        if (msg.job && msg.job.status) div.setAttribute('data-message-job-status', msg.job.status);
        else div.removeAttribute('data-message-job-status');
        if (msg.job && msg.job.backoff_seconds !== undefined && msg.job.backoff_seconds !== null) div.setAttribute('data-message-job-backoff-seconds', msg.job.backoff_seconds);
        else div.removeAttribute('data-message-job-backoff-seconds');
        div.innerHTML = this.messageDivHtml(msg);
      }.bind(this));

      this.updatePendingJobStatus();
      if (shouldScroll) this.scrollToBottom();
    },

    renderNewMessages: function(messages) {
      this.renderMessages(messages);
    },

    isNearBottom: function(list) {
      if (!list) return true;
      return list.scrollHeight - list.scrollTop - list.clientHeight < 80;
    },

    messageDivHtml: function(msg) {
      var name = msg.user_name || (msg.role === 'assistant' ? 'Automyra' : '');
      var nameHtml = name ? '<span class="automyra-chat-message-name">' + this.escapeHtml(name) + '</span>' : '';
      return nameHtml +
        '<div class="automyra-chat-message-content">' + this.buildMessageContent(msg) + '</div>' +
        this.buildJobStatusRow(msg) +
        '<span class="automyra-chat-message-time">' + this.formatTime(msg.created_at) + '</span>';
    },

    buildMessageContent: function(msg) {
      if (msg.role === 'assistant' && msg.status === 'pending') {
        return '<span class="automyra-chat-typing-indicator">' + this.escapeHtml(this.jobStatusText(msg.job)) + '</span>';
      }
      if (msg.role === 'assistant' && (msg.status === 'failed' || (msg.job && ['failed', 'max_steps_reached'].indexOf(String(msg.job.status)) !== -1))) {
        return this.failedJobHtml(msg);
      }
      var html = this.basicMarkdownHtml(msg.content || '');
      if (msg.role === 'assistant' && msg.sources) html += this.sourcesHtml(msg.sources);
      if (msg.role === 'assistant' && msg.job_id && msg.status === 'pending') {
        html += '<p class="buttons automyra-chat-job-actions"><button type="button" class="button-small" data-chat-cancel-job="' + this.cancelJobId(msg) + '">Stop</button></p>';
      } else if (msg.role === 'assistant' && msg.job_id) {
        html += '<p class="buttons automyra-chat-job-actions"><button type="button" class="button-small" data-chat-retry-job="' + this.retryJobId(msg) + '">Regenerate</button></p>';
      }
      return html;
    },

    basicMarkdownHtml: function(text) {
      var source = String(text || '').replace(/\r\n/g, '\n');
      var blocks = [];
      source = source.replace(/```([\w-]+)?\n?([\s\S]*?)```/g, function(match, language, code) {
        var token = '%%AUTOMYRA_CODE_BLOCK_' + blocks.length + '%%';
        var label = language ? '<span class="automyra-chat-code-language">' + this.escapeHtml(language) + '</span>' : '';
        blocks.push('<pre><code>' + label + this.escapeHtml(code.replace(/\n$/, '')) + '</code></pre>');
        return token;
      }.bind(this));

      var lines = source.split('\n');
      var html = [];
      var listType = null;

      var closeList = function() {
        if (listType) {
          html.push('</' + listType + '>');
          listType = null;
        }
      };

      lines.forEach(function(line) {
        var trimmed = line.trim();
        var unordered = trimmed.match(/^[-*]\s+(.+)$/);
        var ordered = trimmed.match(/^\d+[.)]\s+(.+)$/);
        var heading = trimmed.match(/^(#{1,4})\s+(.+)$/);
        var quote = trimmed.match(/^>\s+(.+)$/);

        if (!trimmed) {
          closeList();
          html.push('');
        } else if (unordered) {
          if (listType !== 'ul') { closeList(); html.push('<ul>'); listType = 'ul'; }
          html.push('<li>' + this.inlineMarkdownHtml(unordered[1]) + '</li>');
        } else if (ordered) {
          if (listType !== 'ol') { closeList(); html.push('<ol>'); listType = 'ol'; }
          html.push('<li>' + this.inlineMarkdownHtml(ordered[1]) + '</li>');
        } else {
          closeList();
          if (heading) {
            var level = Math.min(heading[1].length + 3, 6);
            html.push('<h' + level + '>' + this.inlineMarkdownHtml(heading[2]) + '</h' + level + '>');
          } else if (quote) {
            html.push('<blockquote>' + this.inlineMarkdownHtml(quote[1]) + '</blockquote>');
          } else if (/^%%AUTOMYRA_CODE_BLOCK_\d+%%$/.test(trimmed)) {
            html.push(trimmed);
          } else {
            html.push('<p>' + this.inlineMarkdownHtml(line) + '</p>');
          }
        }
      }.bind(this));
      closeList();

      return html.join('').replace(/%%AUTOMYRA_CODE_BLOCK_(\d+)%%/g, function(match, index) {
        return blocks[Number(index)] || '';
      });
    },

    inlineMarkdownHtml: function(text) {
      var html = this.escapeHtml(text || '');
      html = html.replace(/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g, '<a href="$2" rel="noopener noreferrer" target="_blank">$1</a>');
      html = html.replace(/`([^`]+)`/g, '<code>$1</code>');
      html = html.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
      html = html.replace(/\b_([^_]+)_\b/g, '<em>$1</em>');
      return html;
    },

    sourcesHtml: function(sources) {
      var parts = [];
      var tools = sources.tools || sources['tools'] || [];
      if (tools.length) parts.push('tools: ' + tools.join(', '));
      var page = sources.page_context || sources['page_context'];
      if (page && (page.title || page.type || page.id)) parts.push('page: ' + [page.title, page.type, page.id].filter(Boolean).join(' '));
      return parts.length ? '<div class="automyra-chat-sources"><small>Sources: ' + this.escapeHtml(parts.join(' · ')) + '</small></div>' : '';
    },

    buildJobStatusRow: function(msg) {
      if (!msg || !msg.job) return '';

      var status = msg.job.status || msg.status || 'pending';
      var text = this.jobStatusText(msg.job);
      var row = '<div class="automyra-chat-job-status automyra-chat-job-status--' + this.escapeAttribute(status) + '">' + this.escapeHtml(text);
      if (['queued', 'running', 'retrying'].indexOf(String(status)) !== -1) {
        row += ' <button type="button" class="button-small" data-chat-cancel-job="' + this.cancelJobId(msg) + '">Cancel</button>';
      } else if (['failed', 'max_steps_reached'].indexOf(String(status)) !== -1) {
        row += ' <button type="button" class="button-small button-positive" data-chat-retry-job="' + this.retryJobId(msg) + '">Retry</button>' +
          ' <button type="button" class="button-small" data-chat-cancel-job="' + this.cancelJobId(msg) + '">Cancel</button>';
      }
      return row + '</div>';
    },

    renderRunEvent: function(event) {
      if (!event || !event.event_type) return;
      if (String(event.event_type).indexOf('action_proposal.') === 0 || String(event.event_type).indexOf('proposal.') === 0) {
        this.renderProposalEvent(event);
      } else if (event.message) {
        this.appendSystemMessage(event.message);
      }
    },

    renderProposalEvent: function(event) {
      var payload = this.normalizedProposalPayload(event);
      var proposalId = payload.proposal_id;
      if (!proposalId) return;

      var list = document.querySelector('[data-automyra-chat="message-list"]');
      if (!list) return;

      var card = list.querySelector('[data-proposal-id="' + this.escapeSelectorValue(proposalId) + '"]');
      if (!card) {
        card = document.createElement('div');
        card.setAttribute('data-proposal-id', proposalId);
        list.appendChild(card);
      }

      var status = payload.status || event.status || 'pending';
      card.className = 'box automyra-chat-proposal automyra-chat-proposal--' + this.escapeAttribute(status);
      card.innerHTML = this.proposalCardHtml(event, payload, status);
      this.scrollToBottom();
    },

    proposalCardHtml: function(event, payload, status) {
      var proposalId = payload.proposal_id || '';
      var actionType = payload.action_type || 'Automyra action';
      var reason = payload.reason || 'This action can modify Redmica data and requires operator approval.';
      var target = this.proposalTargetText(payload);
      var diff = this.proposalDiffText(payload);
      var html = '<h4>Action proposal</h4>' +
        '<p><strong>Action:</strong> ' + this.escapeHtml(this.titleize(actionType)) + '</p>' +
        (target ? '<p><strong>Target:</strong> ' + this.escapeHtml(target) + '</p>' : '') +
        (diff ? '<pre class="automyra-chat-proposal-diff">' + this.escapeHtml(diff) + '</pre>' : '') +
        '<p class="info">' + this.escapeHtml(reason) + '</p>' +
        '<p>Status: <span class="automyra-chat-proposal-status automyra-chat-proposal-status--' + this.escapeAttribute(status) + '">' + this.escapeHtml(this.titleize(status)) + '</span></p>';

      if (status === 'pending' && payload.can_manage === true) {
        html += '<p class="buttons">' +
          '<button type="button" class="button-positive" data-proposal-action="approve" data-proposal-id="' + this.escapeAttribute(proposalId) + '">Approve</button> ' +
          '<button type="button" class="button" data-proposal-action="reject" data-proposal-id="' + this.escapeAttribute(proposalId) + '">Reject</button>' +
          '</p>';
      }

      if (payload.result && status !== 'pending') {
        html += '<p><strong>Execution result:</strong> ' + this.escapeHtml(this.proposalResultText(payload.result)) + '</p>';
      } else if (status === 'approved') {
        html += '<p><strong>Status update:</strong> Approved; Automyra is applying the action.</p>';
      } else if (status === 'executed') {
        html += '<p><strong>Status update:</strong> Executed; changes were applied.</p>';
      } else if (status === 'rejected') {
        html += '<p><strong>Status update:</strong> Rejected; no changes were applied.</p>';
      }

      return html;
    },

    proposalTargetText: function(payload) {
      var targetType = payload.target_type || (payload.target && payload.target.type) || '';
      var targetId = payload.target_id || (payload.target && payload.target.id) || '';
      if (!targetType && payload.issue_id) targetType = 'Issue';
      if (!targetId && payload.issue_id) targetId = payload.issue_id;
      if (!targetType && payload.task_id) targetType = 'Task';
      if (!targetId && payload.task_id) targetId = payload.task_id;
      if (!targetType && !targetId) return '';
      return targetType + (targetId ? ' #' + targetId : '');
    },

    normalizedProposalPayload: function(event) {
      var payload = this.eventPayload(event);
      if (payload.tool_call && payload.tool_call.input) {
        var merged = {};
        Object.keys(payload.tool_call.input).forEach(function(key) { merged[key] = payload.tool_call.input[key]; });
        Object.keys(payload).forEach(function(key) { merged[key] = payload[key]; });
        payload = merged;
      }
      payload.proposal_id = payload.proposal_id || payload.id;
      return payload;
    },

    proposalDiffText: function(payload) {
      var diff = payload.diff || payload.changes || payload.patch || payload.preview;
      if (diff) return this.compactProposalValue(diff);

      var candidates = ['task', 'issue', 'wiki', 'assignment', 'comment', 'target'];
      var lines = [];
      candidates.forEach(function(key) {
        if (!payload[key] || typeof payload[key] !== 'object') return;
        Object.keys(payload[key]).forEach(function(field) {
          var value = payload[key][field];
          if (value === null || value === undefined || value === '') return;
          lines.push(this.titleize(key) + ' ' + field + ': ' + this.compactProposalValue(value));
        }.bind(this));
      }.bind(this));

      return lines.slice(0, 6).join('\n');
    },

    compactProposalValue: function(value) {
      if (value === null || value === undefined) return '';
      if (typeof value === 'string') return value.length > 240 ? value.slice(0, 237) + '...' : value;
      try {
        var json = JSON.stringify(value);
        return json.length > 240 ? json.slice(0, 237) + '...' : json;
      } catch (error) {
        return String(value);
      }
    },

    proposalResultText: function(result) {
      if (result === null || result === undefined || result === '') return '';
      if (typeof result === 'string') return result;
      if (result.message) return result.message;
      if (result.summary) return result.summary;
      try {
        return JSON.stringify(result);
      } catch (error) {
        return String(result);
      }
    },

    eventPayload: function(event) {
      if (!event || !event.payload) return {};
      if (typeof event.payload === 'object') return event.payload;
      try {
        return JSON.parse(event.payload || '{}');
      } catch (error) {
        return {};
      }
    },

    failedJobHtml: function(msg) {
      var error = msg && msg.job && msg.job.error_summary ? msg.job.error_summary : '';
      var html = '<div class="automyra-chat-error-message">Unable to get response.';
      if (error) html += '<div class="automyra-chat-error-summary">' + this.escapeHtml(error) + '</div>';
      html += '<button type="button" class="automyra-chat-retry-btn" data-chat-retry-job="' + this.retryJobId(msg) + '">Retry?</button> ' +
        '<button type="button" class="button-small" data-chat-cancel-job="' + this.cancelJobId(msg) + '">Cancel</button>';
      return html + '</div>';
    },

    retryJobId: function(msg) {
      return this.escapeAttribute((msg && msg.job && msg.job.id) || (msg && msg.job_id) || '');
    },

    cancelJobId: function(msg) {
      return this.retryJobId(msg);
    },

    retryJob: function(jobId) {
      if (!jobId) return;
      this.showStatus('Retrying...');

      fetch('/automyra_bridge/chat/retry_job', {
        method: 'POST',
        credentials: 'same-origin',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.csrfToken(),
          'Accept': 'application/json'
        },
        body: JSON.stringify({ job_id: jobId })
      })
      .then(function(response) {
        if (!response.ok) throw new Error('Retry failed: ' + response.status);
        return response.json();
      })
      .then(function(data) {
        this.hideStatus();
        if (data && data.run_id) this.activeRunId = data.run_id;
        if (data && data.run_status) this.showStatus(this.titleize(data.run_status));
        this.refreshHistory();
        this.pollForUpdates();
        if (this.activeRunId) this.fetchRunEvents(this.activeRunId);
      }.bind(this))
      .catch(function(error) {
        this.hideStatus();
        this.appendSystemMessage('Error: ' + error.message);
        this.scrollToBottom();
      }.bind(this));
    },

    cancelJob: function(jobId) {
      if (!jobId) return;
      this.showStatus('Cancelling...');

      fetch('/automyra_bridge/chat/cancel_job', {
        method: 'POST',
        credentials: 'same-origin',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.csrfToken(),
          'Accept': 'application/json'
        },
        body: JSON.stringify({ job_id: jobId })
      })
      .then(function(response) {
        if (!response.ok) throw new Error('Cancel failed: ' + response.status);
        return response.json();
      })
      .then(function(data) {
        this.hideStatus();
        if (data && data.run_id) this.activeRunId = data.run_id;
        if (data && data.run_status) this.showStatus(this.titleize(data.run_status));
        this.refreshHistory();
        this.pollForUpdates();
        if (this.activeRunId) this.fetchRunEvents(this.activeRunId);
      }.bind(this))
      .catch(function(error) {
        this.hideStatus();
        this.appendSystemMessage('Error: ' + error.message);
        this.scrollToBottom();
      }.bind(this));
    },

    newThread: function() {
      var pageContext = this.getPageContext();
      fetch('/automyra_bridge/chat/new_thread', {
        method: 'POST',
        credentials: 'same-origin',
        headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': this.csrfToken(), 'Accept': 'application/json' },
        body: JSON.stringify({ thread_kind: this.threadKind, page_type: pageContext.page_type, page_id: pageContext.page_id, project_id: pageContext.project_id, url_path: pageContext.url_path, page_title: pageContext.page_title })
      }).then(function(response) {
        if (!response.ok) throw new Error('New thread failed: ' + response.status);
        return response.json();
      }).then(function(data) {
        this.updateThreadState(data);
        var list = document.querySelector('[data-automyra-chat="message-list"]');
        if (list) list.innerHTML = '';
        this.renderMessages(data.messages || []);
      }.bind(this)).catch(function(error) {
        this.appendSystemMessage('Error: ' + error.message);
      }.bind(this));
    },

    appendUserMessage: function(content) {
      this.renderNewMessages([{
        id: 'temp-' + Date.now(),
        role: 'user',
        status: 'sent',
        content: content,
        created_at: new Date().toISOString()
      }]);
    },

    appendSystemMessage: function(content) {
      this.renderNewMessages([{
        id: 'temp-' + Date.now(),
        role: 'system',
        status: 'delivered',
        content: content,
        created_at: new Date().toISOString()
      }]);
    },

    showStatus: function(text) {
      var status = this.statusElement();
      if (status) {
        status.textContent = text;
        status.classList.remove('automyra-chat-hidden');
      }
    },

    hideStatus: function() {
      var status = this.statusElement();
      if (status) {
        status.classList.add('automyra-chat-hidden');
      }
    },

    statusElement: function() {
      var status = document.querySelector('[data-automyra-chat="status"]');
      if (status) return status;

      var panel = document.getElementById('automyra-chat-panel');
      var list = document.querySelector('[data-automyra-chat="message-list"]');
      if (!panel || !list || !list.parentNode) return null;

      status = document.createElement('div');
      status.setAttribute('data-automyra-chat', 'status');
      status.className = 'automyra-chat-status automyra-chat-hidden';
      list.parentNode.insertBefore(status, list.nextSibling);
      return status;
    },

    updatePendingJobStatus: function() {
      var pending = document.querySelector('[data-automyra-chat="message-list"] [data-message-status="pending"]');
      if (!pending) {
        this.hideStatus();
        return;
      }

      var jobStatus = pending.getAttribute('data-message-job-status') || '';
      var backoffSeconds = pending.getAttribute('data-message-job-backoff-seconds') || '';
      var text = 'Automyra is thinking...';
      if (jobStatus === 'queued') text = 'Automyra is queued...';
      else if (jobStatus === 'retrying') text = backoffSeconds ? 'Automyra is retrying; next attempt in ' + backoffSeconds + 's...' : 'Automyra is retrying...';
      else if (jobStatus === 'stale' || jobStatus === 'delayed' || jobStatus === 'worker_delayed') text = backoffSeconds ? 'Automyra is delayed (' + backoffSeconds + 's)...' : 'Automyra is delayed...';
      else if (jobStatus === 'running') text = 'Automyra is thinking...';
      this.showStatus(text);
    },

    scrollToBottom: function() {
      var list = document.querySelector('[data-automyra-chat="message-list"]');
      if (list) {
        list.scrollTop = list.scrollHeight;
      }
    },

    markRead: function() {
      this.updateUnreadBadge(0);
      var thread = this.currentThread() || {};

      if (!thread.id) return;

      fetch('/automyra_bridge/chat/mark_read', {
        method: 'POST',
        credentials: 'same-origin',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.csrfToken(),
          'Accept': 'application/json'
        },
        body: JSON.stringify({ thread_id: thread.id })
      }).catch(function() {
        console.warn('Automyra chat mark-read failed');
      });
    },

    setLoading: function(isLoading) {
      this.isLoading = isLoading === true;
      var sendBtn = document.querySelector('[data-automyra-chat="send-btn"], #chat-submit');
      var input = document.querySelector('[data-automyra-chat="input"], #chat-input');

      if (sendBtn && sendBtn.getAttribute('data-original-text') === null) {
        sendBtn.setAttribute('data-original-text', sendBtn.textContent);
      }

      if (sendBtn) {
        sendBtn.disabled = this.isLoading;
        sendBtn.classList.toggle('automyra-chat-send-btn--loading', this.isLoading);
        sendBtn.textContent = this.isLoading ? 'Sending…' : sendBtn.getAttribute('data-original-text');
      }
      if (input) input.disabled = this.isLoading;
    },

    updateUnreadBadge: function(count) {
      var badge = document.querySelector('.automyra-chat-unread-badge');
      if (badge) {
        if (count > 0) {
          badge.textContent = count;
          badge.classList.remove('automyra-chat-hidden');
        } else {
          badge.classList.add('automyra-chat-hidden');
        }
      }
    },

    getPageContext: function() {
      var meta = document.querySelector('meta[name="automyra-chat-context"]');
      if (meta) {
        try {
          return JSON.parse(meta.content);
        } catch (error) {
          console.warn('Automyra chat context parse error:', error);
        }
      }

      var panel = document.getElementById('automyra-chat-panel');
      if (panel) {
        return {
          page_type: panel.getAttribute('data-page-type') || '',
          page_id: panel.getAttribute('data-page-id') || '',
          project_id: panel.getAttribute('data-project-id') || '',
          url_path: panel.getAttribute('data-url-path') || window.location.pathname,
          page_title: panel.getAttribute('data-page-title') || document.title
        };
      }

      return {
        page_type: '',
        page_id: '',
        project_id: '',
        url_path: window.location.pathname,
        page_title: document.title
      };
    },

    csrfToken: function() {
      var meta = document.querySelector('meta[name="csrf-token"]');
      return meta ? meta.content : '';
    },

    escapeHtml: function(text) {
      var div = document.createElement('div');
      div.textContent = text;
      return div.innerHTML;
    },

    escapeAttribute: function(text) {
      return String(text).replace(/[^a-z0-9_-]/gi, '');
    },

    escapeSelectorValue: function(text) {
      if (window.CSS && typeof window.CSS.escape === 'function') return window.CSS.escape(String(text));
      return String(text).replace(/(["\\])/g, '\\$1');
    },

    titleize: function(text) {
      text = String(text || '');
      return text.charAt(0).toUpperCase() + text.slice(1).replace(/_/g, ' ');
    },

    formatTime: function(isoString) {
      if (!isoString) return '';
      var date = new Date(isoString);
      return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    },

    currentThread: function() {
      var panel = document.getElementById('automyra-chat-panel');
      if (!panel) return null;

      return {
        id: panel.getAttribute('data-thread-id'),
        kind: panel.getAttribute('data-thread-kind') || this.threadKind
      };
    },

    detectThreadKind: function() {
      var panel = document.getElementById('automyra-chat-panel');
      if (panel) {
        this.threadKind = panel.getAttribute('data-thread-kind') || this.threadKind;
      }
    },

    detectLastMessageId: function() {
      this.lastMessageId = 0;
      var messages = document.querySelectorAll('[data-automyra-chat="message-list"] [data-message-id]');
      messages.forEach(function(message) {
        var id = parseInt(message.getAttribute('data-message-id'), 10);
        if (id > this.lastMessageId) this.lastMessageId = id;
      }.bind(this));
    },

    detectLastSeenUpdateAt: function() {
      this.lastSeenUpdateAt = '';
      var messages = document.querySelectorAll('[data-automyra-chat="message-list"] [data-message-updated-at]');
      messages.forEach(function(message) {
        var updatedAt = message.getAttribute('data-message-updated-at') || '';
        if (updatedAt > this.lastSeenUpdateAt) this.lastSeenUpdateAt = updatedAt;
      }.bind(this));
    },

    updateCursors: function(data) {
      if (!data) return;
      if (data.last_message_id !== undefined && data.last_message_id !== null) {
        this.lastMessageId = parseInt(data.last_message_id, 10) || 0;
      }
      if (data.last_seen_update_at !== undefined && data.last_seen_update_at !== null) {
        this.lastSeenUpdateAt = data.last_seen_update_at || '';
      }
    },

    resetCursors: function() {
      this.lastMessageId = 0;
      this.lastSeenUpdateAt = '';
    },

    toggleThread: function() {
      this.threadKind = this.threadKind === 'page' ? 'global' : 'page';
      var pageContext = this.getPageContext();
      this.showStatus('Switching thread...');

      fetch('/automyra_bridge/chat/toggle_thread', {
        method: 'POST',
        credentials: 'same-origin',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.csrfToken(),
          'Accept': 'application/json'
        },
        body: JSON.stringify({
          thread_kind: this.threadKind,
          page_type: pageContext.page_type,
          page_id: pageContext.page_id,
          project_id: pageContext.project_id,
          url_path: pageContext.url_path,
          page_title: pageContext.page_title
        })
      })
      .then(function(response) {
        if (!response.ok) throw new Error('Toggle failed: ' + response.status);
        if (response.status === 204) return {};
        return response.json();
      })
      .then(function(data) {
        this.hideStatus();
        this.updateThreadState(data);
        this.replaceMessageList(data);
        this.refreshHistory();
      }.bind(this))
      .catch(function(error) {
        this.hideStatus();
        this.showStatus(error.message);
        console.warn('Automyra chat thread toggle failed:', error);
      }.bind(this));
    },

    replaceMessageList: function(data) {
      var list = document.querySelector('[data-automyra-chat="message-list"]');
      if (!list || !data) return;

      if (typeof data.html === 'string') {
        list.innerHTML = data.html;
      } else if (typeof data.messages_html === 'string') {
        list.innerHTML = data.messages_html;
      } else if (data.messages) {
        list.innerHTML = '';
        this.resetCursors();
        this.renderMessages(data.messages);
      }

      this.detectLastMessageId();
      this.detectLastSeenUpdateAt();
      this.updateCursors(data);
      this.updatePendingJobStatus();
      this.scrollToBottom();
    },

    refreshHistory: function() {
      if (!this.panelOpen) return Promise.resolve();

      var thread = this.currentThread();
      var params = [];
      if (thread && thread.id) params.push('thread_id=' + encodeURIComponent(thread.id));
      if (thread && thread.kind) params.push('thread_kind=' + encodeURIComponent(thread.kind));

      return fetch('/automyra_bridge/chat/history' + (params.length ? '?' + params.join('&') : ''), {
        credentials: 'same-origin',
        headers: {
          'X-CSRF-Token': this.csrfToken(),
          'Accept': 'application/json'
        }
      })
      .then(function(response) {
        if (!response.ok) throw new Error('History failed: ' + response.status);
        if (response.status === 204) return {};
        return response.json();
      })
      .then(function(data) {
        this.updateThreadState(data);
        this.replaceMessageList(data);
      }.bind(this))
      .catch(function() {
        console.warn('Automyra chat history refresh failed');
      });
    },

    responseMessages: function(data) {
      if (!data) return [];
      if (data.messages) return data.messages;
      var messages = [];
      if (data.message) messages.push(data.message);
      if (data.user_message) messages.push(data.user_message);
      if (data.assistant_placeholder) messages.push(data.assistant_placeholder);
      if (data.assistant_message) messages.push(data.assistant_message);
      return messages;
    },

    jobStatusText: function(job) {
      if (!job || !job.status) return 'Automyra is thinking...';
      if (job.status === 'queued') return 'Automyra is queued...';
      if (job.status === 'running') return 'Automyra is thinking...';
      if (job.status === 'retrying') return 'Automyra is retrying (' + (job.retry_count || 0) + '/' + (job.max_retries || 0) + ')...';
      if (job.status === 'failed') return job.error_summary ? 'Automyra failed.' : 'Unable to get response.';
      if (job.status === 'stale' || job.status === 'delayed' || job.status === 'worker_delayed') return job.backoff_seconds ? 'Automyra is delayed (' + job.backoff_seconds + 's)...' : 'Automyra is delayed...';
      return 'Automyra is ' + job.status + '...';
    },

    reconcileTempUserMessage: function(content, message) {
      if (!message || !message.id || message.role !== 'user') return;
      var list = document.querySelector('[data-automyra-chat="message-list"]');
      if (!list) return;

      var tempMessages = list.querySelectorAll('[data-message-id^="temp-"]');
      for (var i = tempMessages.length - 1; i >= 0; i--) {
        var temp = tempMessages[i];
        if (temp.getAttribute('data-message-status') === 'sent' && temp.textContent.indexOf(content) !== -1) {
          temp.parentNode.removeChild(temp);
          return;
        }
      }
    },

    updateThreadState: function(data) {
      var panel = document.getElementById('automyra-chat-panel');
      var toggleBtn = document.querySelector('[data-automyra-chat="toggle-thread"]');
      if (!data) return;

      if (data.thread_kind) this.threadKind = data.thread_kind;
      if (panel) {
        if (data.thread_id !== undefined && data.thread_id !== null) panel.setAttribute('data-thread-id', data.thread_id);
        if (data.thread_kind) panel.setAttribute('data-thread-kind', data.thread_kind);
        else panel.setAttribute('data-thread-kind', this.threadKind);
        if (data.unread_count !== undefined) panel.setAttribute('data-unread-count', data.unread_count);
      }
      if (toggleBtn) toggleBtn.textContent = this.threadKind === 'global' ? 'Global' : 'Page';
      if (data.unread_count !== undefined) this.updateUnreadBadge(data.unread_count);
    },

    handleProposalAction: function(button) {
      if (!button || button.disabled) return;

      var action = button.getAttribute('data-proposal-action');
      var proposal = button.closest('[data-proposal-id]');
      var proposalId = proposal ? proposal.getAttribute('data-proposal-id') : button.getAttribute('data-proposal-id');
      var endpoint = button.getAttribute('data-proposal-url') || (action === 'approve' ? '/automyra_bridge/proposals/' + proposalId + '/approve' : '/automyra_bridge/proposals/' + proposalId + '/reject');
      var buttons = proposal ? proposal.querySelectorAll('[data-proposal-action]') : [button];
      var originalText = button.textContent;

      if (!proposalId || (action !== 'approve' && action !== 'reject')) return;

      buttons.forEach(function(btn) { btn.disabled = true; });
      button.textContent = action === 'approve' ? 'Approving...' : 'Rejecting...';
      this.showStatus(button.textContent);

      fetch(endpoint, {
        method: 'POST',
        credentials: 'same-origin',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.csrfToken(),
          'Accept': 'application/json'
        },
        body: JSON.stringify({ proposal_id: proposalId })
      })
      .then(function(response) {
        if (!response.ok) throw new Error('Proposal ' + action + ' failed: ' + response.status);
        if (response.status === 204) return {};
        return response.json();
      })
      .then(function(data) {
        this.hideStatus();
        this.updateProposalStatus(proposal, data.status || (action === 'approve' ? 'approved' : 'rejected'));
        this.pollForUpdates();
      }.bind(this))
      .catch(function(error) {
        button.textContent = originalText;
        buttons.forEach(function(btn) { btn.disabled = false; });
        this.showStatus(error.message);
        console.warn('Automyra chat proposal action failed:', error);
      }.bind(this));
    },

    updateProposalStatus: function(proposal, status) {
      if (!proposal) return;

      proposal.className = proposal.className.replace(/automyra-chat-proposal--\S+/g, '').trim() + ' automyra-chat-proposal--' + this.escapeAttribute(status);
      var statusEl = proposal.querySelector('.automyra-chat-proposal-status');
      if (statusEl) {
        statusEl.className = statusEl.className.replace(/automyra-chat-proposal-status--\S+/g, '').trim() + ' automyra-chat-proposal-status--' + this.escapeAttribute(status);
        statusEl.textContent = status.charAt(0).toUpperCase() + status.slice(1);
      }
      var buttons = proposal.querySelector('.buttons');
      if (buttons) buttons.parentNode.removeChild(buttons);
      if (!proposal.querySelector('[data-proposal-local-result]')) {
        var result = document.createElement('p');
        result.setAttribute('data-proposal-local-result', 'true');
        result.innerHTML = '<strong>Status update:</strong> ' + this.escapeHtml(status === 'rejected' ? 'Rejected; no changes were applied.' : 'Approved; Automyra is applying the action.');
        proposal.appendChild(result);
      }
    }
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function() { AutomyraChat.init(); });
  } else {
    AutomyraChat.init();
  }

  window.AutomyraChat = AutomyraChat;
}());
