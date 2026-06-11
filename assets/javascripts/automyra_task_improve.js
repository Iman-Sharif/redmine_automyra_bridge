(function() {
  function field(name) {
    return document.querySelector('[name="task[' + name + ']"]');
  }

  function applySuggestions(task) {
    if (!task) return;
    if (task.title && field('title')) field('title').value = task.title;
    if (task.notes && field('notes')) field('notes').value = task.notes;
    if (task.category_id && field('category_id')) field('category_id').value = task.category_id;
  }

  function showStatus(trigger, message, isError) {
    var target = document.querySelector('[data-automyra-status]');
    if (!target) {
      target = document.createElement('span');
      target.setAttribute('data-automyra-status', 'true');
      trigger.insertAdjacentElement('afterend', target);
    }
    target.className = isError ? 'error' : 'icon icon-checked';
    target.textContent = ' ' + message;
  }

  function improve(trigger) {
    var token = document.querySelector('meta[name="csrf-token"]');
    var body = new URLSearchParams();
    ['title', 'notes', 'status', 'priority', 'due_date', 'project_id', 'category_id'].forEach(function(name) {
      var input = field(name);
      if (input) body.append('task[' + name + ']', input.value || '');
    });

    trigger.disabled = true;
    showStatus(trigger, 'Contacting Automyra...', false);
    fetch(trigger.dataset.automyraImproveUrl, {
      method: 'POST',
      credentials: 'same-origin',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'X-CSRF-Token': token ? token.content : ''
      },
      body: body.toString()
    }).then(function(response) {
      return response.json().then(function(json) {
        if (!response.ok) throw new Error(json.error || 'Automyra request failed.');
        return json;
      });
    }).then(function(json) {
      applySuggestions(json.task);
      showStatus(trigger, 'Automyra suggestions applied.', false);
    }).catch(function(error) {
      showStatus(trigger, error.message, true);
    }).finally(function() {
      trigger.disabled = false;
    });
  }

  document.addEventListener('click', function(event) {
    var trigger = event.target.closest('[data-automyra-improve-url]');
    if (!trigger) return;
    event.preventDefault();
    improve(trigger);
  });
}());
