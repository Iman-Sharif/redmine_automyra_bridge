// Wiki Hub Bulk Operations JavaScript
// Phase 2: Multi-select and bulk actions

document.addEventListener('DOMContentLoaded', function() {
  const bulkToolbar = document.querySelector('[data-testid="wiki-hub-bulk-toolbar"]');
  const bulkForm = document.getElementById('wiki-hub-bulk-form');
  const checkboxes = document.querySelectorAll('.page-card-checkbox');
  const selectAllCheckbox = document.getElementById('select-all-pages');
  
  if (!bulkToolbar || !bulkForm) return;
  
  let selectedPages = new Set();
  
  // Update toolbar visibility and count
  function updateBulkToolbar() {
    const count = selectedPages.size;
    const countDisplay = bulkToolbar.querySelector('.bulk-selected-count');
    
    if (countDisplay) {
      countDisplay.textContent = count;
    }
    
    if (count > 0) {
      bulkToolbar.style.display = 'flex';
    } else {
      bulkToolbar.style.display = 'none';
    }
  }
  
  // Handle individual checkbox changes
  checkboxes.forEach(function(checkbox) {
    checkbox.addEventListener('change', function() {
      const pageId = this.dataset.pageId;
      
      if (this.checked) {
        selectedPages.add(pageId);
      } else {
        selectedPages.delete(pageId);
      }
      
      updateBulkToolbar();
    });
  });
  
  // Handle select all (if implemented)
  if (selectAllCheckbox) {
    selectAllCheckbox.addEventListener('change', function() {
      checkboxes.forEach(function(checkbox) {
        checkbox.checked = selectAllCheckbox.checked;
        const pageId = checkbox.dataset.pageId;
        
        if (selectAllCheckbox.checked) {
          selectedPages.add(pageId);
        } else {
          selectedPages.delete(pageId);
        }
      });
      
      updateBulkToolbar();
    });
  }
  
  // Bulk action handlers
  const bulkDeleteBtn = document.querySelector('.bulk-action-delete');
  const bulkTagBtn = document.querySelector('.bulk-action-tag');
  const bulkCategorizeBtn = document.querySelector('.bulk-action-categorize');
  const bulkDuplicateBtn = document.querySelector('.bulk-action-duplicate');
  const bulkClearBtn = document.querySelector('.bulk-action-clear');
  
  // Clear selection
  if (bulkClearBtn) {
    bulkClearBtn.addEventListener('click', function(e) {
      e.preventDefault();
      selectedPages.clear();
      checkboxes.forEach(function(cb) { cb.checked = false; });
      updateBulkToolbar();
    });
  }
  
  // Delete action
  if (bulkDeleteBtn) {
    bulkDeleteBtn.addEventListener('click', function(e) {
      e.preventDefault();
      if (selectedPages.size === 0) return;
      
      if (confirm(this.dataset.confirm)) {
        submitBulkAction('delete');
      }
    });
  }
  
  // Tag action
  if (bulkTagBtn) {
    bulkTagBtn.addEventListener('click', function(e) {
      e.preventDefault();
      if (selectedPages.size === 0) return;
      
      const tagNames = prompt('Enter tags (comma-separated):');
      if (tagNames) {
        submitBulkAction('tag', { tag_names: tagNames });
      }
    });
  }
  
  // Categorize action
  if (bulkCategorizeBtn) {
    bulkCategorizeBtn.addEventListener('click', function(e) {
      e.preventDefault();
      if (selectedPages.size === 0) return;
      
      const category = prompt('Enter category:');
      if (category) {
        submitBulkAction('categorize', { category: category });
      }
    });
  }
  
  // Duplicate action
  if (bulkDuplicateBtn) {
    bulkDuplicateBtn.addEventListener('click', function(e) {
      e.preventDefault();
      if (selectedPages.size === 0) return;
      
      if (confirm('Duplicate ' + selectedPages.size + ' pages?')) {
        submitBulkAction('duplicate');
      }
    });
  }
  
  // Submit bulk action
  function submitBulkAction(action, extraParams = {}) {
    const form = document.createElement('form');
    form.method = 'POST';
    form.action = '/knowledge_hub/bulk_action';
    
    // Add authenticity token
    const token = document.querySelector('meta[name="csrf-token"]')?.content;
    if (token) {
      const tokenInput = document.createElement('input');
      tokenInput.type = 'hidden';
      tokenInput.name = 'authenticity_token';
      tokenInput.value = token;
      form.appendChild(tokenInput);
    }
    
    // Add bulk action
    const actionInput = document.createElement('input');
    actionInput.type = 'hidden';
    actionInput.name = 'bulk_action';
    actionInput.value = action;
    form.appendChild(actionInput);
    
    // Add page IDs
    selectedPages.forEach(function(pageId) {
      const input = document.createElement('input');
      input.type = 'hidden';
      input.name = 'page_ids[]';
      input.value = pageId;
      form.appendChild(input);
    });
    
    // Add extra params
    Object.keys(extraParams).forEach(function(key) {
      const input = document.createElement('input');
      input.type = 'hidden';
      input.name = key;
      input.value = extraParams[key];
      form.appendChild(input);
    });
    
    document.body.appendChild(form);
    form.submit();
  }
  
  // Project Tree Toggle Functionality
  const projectToggles = document.querySelectorAll('.project-tree-toggle');
  
  projectToggles.forEach(function(toggle) {
    toggle.addEventListener('click', function(e) {
      e.preventDefault();
      e.stopPropagation();
      
      const projectItem = this.closest('.project-tree-item');
      const content = projectItem.querySelector('.project-tree-content');
      const icon = this.querySelector('.toggle-icon');
      
      if (content.style.display === 'none') {
        content.style.display = 'block';
        icon.textContent = '▼';
        this.setAttribute('aria-expanded', 'true');
      } else {
        content.style.display = 'none';
        icon.textContent = '▶';
        this.setAttribute('aria-expanded', 'false');
      }
    });
  });
  
  // Phase 3: Search Autocomplete
  const searchInput = document.getElementById('wiki-hub-search-input');
  
  if (searchInput) {
    let debounceTimer;
    let suggestionsContainer = null;
    
    searchInput.addEventListener('input', function() {
      clearTimeout(debounceTimer);
      const term = this.value.trim();
      
      if (term.length < 2) {
        hideSuggestions();
        return;
      }
      
      debounceTimer = setTimeout(function() {
        fetchSearchSuggestions(term);
      }, 200);
    });
    
    // Hide suggestions on click outside
    document.addEventListener('click', function(e) {
      if (!searchInput.contains(e.target) && (!suggestionsContainer || !suggestionsContainer.contains(e.target))) {
        hideSuggestions();
      }
    });
    
    function fetchSearchSuggestions(term) {
      fetch(`/knowledge_hub/search/suggestions?term=${encodeURIComponent(term)}`, {
        headers: {
          'Accept': 'application/json'
        }
      })
      .then(response => response.json())
      .then(data => {
        showSuggestions(data.suggestions);
      })
      .catch(error => {
        console.error('Error fetching suggestions:', error);
      });
    }
    
    function showSuggestions(suggestions) {
      hideSuggestions();
      
      if (suggestions.length === 0) return;
      
      suggestionsContainer = document.createElement('div');
      suggestionsContainer.className = 'search-suggestions';
      suggestionsContainer.setAttribute('data-testid', 'wiki-hub-search-suggestions');
      
      const list = document.createElement('ul');
      list.className = 'suggestions-list';
      
      suggestions.forEach(function(suggestion) {
        const li = document.createElement('li');
        li.className = 'suggestion-item';
        li.textContent = suggestion;
        li.addEventListener('click', function() {
          searchInput.value = suggestion;
          hideSuggestions();
          // Optionally submit the form
          // searchInput.closest('form').submit();
        });
        list.appendChild(li);
      });
      
      suggestionsContainer.appendChild(list);
      searchInput.parentNode.appendChild(suggestionsContainer);
    }
    
    function hideSuggestions() {
      if (suggestionsContainer) {
        suggestionsContainer.remove();
        suggestionsContainer = null;
      }
    }
  }
  
  // Phase 5: Accessibility - Keyboard navigation for page cards
  const pageCards = document.querySelectorAll('.wiki-hub-page-card');
  
  pageCards.forEach(function(card) {
    card.setAttribute('tabindex', '0');
    card.setAttribute('role', 'article');
    
    card.addEventListener('keydown', function(e) {
      const cards = Array.from(document.querySelectorAll('.wiki-hub-page-card'));
      const currentIndex = cards.indexOf(this);
      let nextIndex;
      
      switch(e.key) {
        case 'ArrowRight':
          e.preventDefault();
          nextIndex = currentIndex + 1;
          if (nextIndex < cards.length) {
            cards[nextIndex].focus();
            cards[nextIndex].scrollIntoView({ behavior: 'smooth', block: 'nearest' });
          }
          break;
        case 'ArrowLeft':
          e.preventDefault();
          nextIndex = currentIndex - 1;
          if (nextIndex >= 0) {
            cards[nextIndex].focus();
            cards[nextIndex].scrollIntoView({ behavior: 'smooth', block: 'nearest' });
          }
          break;
        case 'ArrowDown':
          e.preventDefault();
          nextIndex = currentIndex + 3;
          if (nextIndex < cards.length) {
            cards[nextIndex].focus();
            cards[nextIndex].scrollIntoView({ behavior: 'smooth', block: 'nearest' });
          }
          break;
        case 'ArrowUp':
          e.preventDefault();
          nextIndex = currentIndex - 3;
          if (nextIndex >= 0) {
            cards[nextIndex].focus();
            cards[nextIndex].scrollIntoView({ behavior: 'smooth', block: 'nearest' });
          }
          break;
        case 'Enter':
          // Click the main link
          const mainLink = this.querySelector('.wiki-hub-page-title a');
          if (mainLink) {
            mainLink.click();
          }
          break;
      }
    });
  });
  
  // Phase 5: Accessibility - Announce changes to screen readers
  function announceToScreenReader(message) {
    const announcement = document.createElement('div');
    announcement.setAttribute('role', 'status');
    announcement.setAttribute('aria-live', 'polite');
    announcement.setAttribute('aria-atomic', 'true');
    announcement.className = 'visually-hidden';
    announcement.textContent = message;
    
    document.body.appendChild(announcement);
    
    setTimeout(function() {
      if (announcement.parentNode) {
        document.body.removeChild(announcement);
      }
    }, 1000);
  }
  
  // Announce bulk selection changes
  const originalCheckboxes = document.querySelectorAll('.page-card-checkbox');
  originalCheckboxes.forEach(function(checkbox) {
    checkbox.addEventListener('change', function() {
      const checkedCount = document.querySelectorAll('.page-card-checkbox:checked').length;
      if (checkedCount > 0) {
        announceToScreenReader(checkedCount + ' items selected');
      }
    });
  });
});
