window.WikiHub = window.WikiHub || {};

(function() {
  function onReady(callback) {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', callback);
    } else {
      callback();
    }
  }

  onReady(function() {
    var hub = document.querySelector('.wiki-hub');
    if (!hub) return;

    var sidebar = hub.querySelector('.wiki-hub-sidebar');
    var sidebarToggle = hub.querySelector('.wiki-hub-sidebar-toggle');
    var sidebarClose = hub.querySelector('.wiki-hub-sidebar-close');
    var sidebarOverlay = hub.querySelector('.wiki-hub-sidebar-overlay');
    var filtersToggle = hub.querySelector('.wiki-hub-filters-toggle');
    var filtersForm = hub.querySelector('.wiki-hub-filters-form');
    var desktopCollapsedQuery = window.matchMedia('(min-width: 1025px)');
    var mobileQuery = window.matchMedia('(max-width: 768px)');

    function setSidebarState(isOpen) {
      if (!sidebar || !sidebarToggle) return;

      hub.classList.toggle('sidebar-open', isOpen);
      sidebar.setAttribute('aria-hidden', isOpen ? 'false' : mobileQuery.matches ? 'true' : 'false');
      sidebarToggle.setAttribute('aria-expanded', isOpen ? 'true' : 'false');
      if (sidebarClose) {
        sidebarClose.setAttribute('aria-expanded', isOpen ? 'true' : 'false');
      }
      if (sidebarOverlay) {
        sidebarOverlay.hidden = !isOpen;
      }
      document.body.classList.toggle('wiki-hub-mobile-nav-open', isOpen && mobileQuery.matches);
    }

    function syncSidebarForViewport() {
      if (!sidebar || !sidebarToggle) return;

      if (mobileQuery.matches) {
        setSidebarState(false);
      } else {
        hub.classList.remove('sidebar-open');
        sidebar.removeAttribute('aria-hidden');
        sidebarToggle.setAttribute('aria-expanded', hub.classList.contains('sidebar-collapsed') ? 'false' : 'true');
        if (sidebarClose) sidebarClose.setAttribute('aria-expanded', 'true');
        if (sidebarOverlay) sidebarOverlay.hidden = true;
        document.body.classList.remove('wiki-hub-mobile-nav-open');
      }
    }

    if (sidebarToggle && sidebar) {
      sidebarToggle.addEventListener('click', function() {
        if (mobileQuery.matches) {
          setSidebarState(!hub.classList.contains('sidebar-open'));
          return;
        }

        if (desktopCollapsedQuery.matches) {
          var collapsed = hub.classList.toggle('sidebar-collapsed');
          sidebarToggle.setAttribute('aria-expanded', collapsed ? 'false' : 'true');
        }
      });
    }

    if (sidebarClose) {
      sidebarClose.addEventListener('click', function() {
        setSidebarState(false);
      });
    }

    if (sidebarOverlay) {
      sidebarOverlay.addEventListener('click', function() {
        setSidebarState(false);
      });
    }

    document.addEventListener('keydown', function(event) {
      if (event.key === 'Escape' && hub.classList.contains('sidebar-open')) {
        setSidebarState(false);
        if (sidebarToggle) sidebarToggle.focus();
      }
    });

    function setFilterState(expanded) {
      if (!filtersToggle || !filtersForm) return;
      filtersToggle.setAttribute('aria-expanded', expanded ? 'true' : 'false');
      filtersForm.hidden = !expanded;
      filtersForm.classList.toggle('is-open', expanded);
    }

    if (filtersToggle && filtersForm) {
      filtersToggle.addEventListener('click', function() {
        setFilterState(filtersToggle.getAttribute('aria-expanded') !== 'true');
      });

      if (mobileQuery.matches) {
        setFilterState(false);
      } else {
        setFilterState(true);
      }
    }

    function syncFiltersForViewport() {
      if (!filtersToggle || !filtersForm) return;
      setFilterState(!mobileQuery.matches);
    }

    syncSidebarForViewport();
    syncFiltersForViewport();
    window.addEventListener('resize', function() {
      syncSidebarForViewport();
      syncFiltersForViewport();
    });
  });
})();
