/* ----------------------------------------------------
   Ingress Scanner Event Console Controller (Vanilla JS)
   ---------------------------------------------------- */

document.addEventListener('DOMContentLoaded', () => {
  // Constants & State
  const EVENTS_DATA_URL = 'events.json';
  let allEvents = [];
  let activeFilter = 'all';

  // DOM Elements
  const eventsGrid = document.getElementById('events-grid');
  const loader = document.getElementById('loader');
  const emptyState = document.getElementById('empty-state');
  const statusNode = document.getElementById('status-node');
  const statusText = document.getElementById('status-text');
  const dbCountDisplay = document.getElementById('db-count');
  const tzDisplay = document.getElementById('current-timezone-display');

  // Filter Buttons
  const filterBtns = {
    all: document.getElementById('filter-all'),
    active: document.getElementById('filter-active'),
    upcoming: document.getElementById('filter-upcoming'),
    past: document.getElementById('filter-past')
  };

  // Initialize
  initConsole();

  async function initConsole() {
    // Show current local timezone in footer
    try {
      const tzName = Intl.DateTimeFormat().resolvedOptions().timeZone || 'Local';
      tzDisplay.textContent = tzName;
    } catch (e) {
      tzDisplay.textContent = 'UTC';
    }

    // Load data
    await loadEventsData();

    // Register filter events
    Object.keys(filterBtns).forEach(key => {
      if (filterBtns[key]) {
        filterBtns[key].addEventListener('click', () => setFilter(key));
      }
    });
  }

  async function loadEventsData() {
    showLoader(true);
    try {
      const response = await fetch(EVENTS_DATA_URL);
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }
      const articles = await response.ok ? await response.json() : [];
      
      // Flatten articles into individual sub-events
      allEvents = [];
      articles.forEach(art => {
        if (art.events && Array.isArray(art.events)) {
          art.events.forEach(evt => {
            allEvents.push({
              articleId: art.id,
              articleTitle: art.title,
              articleUrl: art.url,
              publishedAt: art.published_at,
              name: evt.name,
              startTime: evt.start_time,
              endTime: evt.end_time,
              timingType: evt.timing_type,
              changes: evt.changes || []
            });
          });
        }
      });

      // Sort: Active first, then Upcoming (soonest first), then Past (newest first)
      sortEvents();

      // Render
      renderEvents();
      updateStatusPanel();

    } catch (error) {
      console.error('Failed to load Ingress events data:', error);
      showLoader(false);
      showEmptyState(true);
      statusText.textContent = 'ERROR';
      statusText.style.color = '#ff2a6d';
    }
  }

  function sortEvents() {
    const now = new Date();
    
    allEvents.forEach(evt => {
      evt.computedState = getEventState(evt, now);
    });

    allEvents.sort((a, b) => {
      // Order priority: active (0), upcoming (1), past (2)
      const stateOrder = { 'active': 0, 'upcoming': 1, 'past': 2 };
      if (stateOrder[a.computedState] !== stateOrder[b.computedState]) {
        return stateOrder[a.computedState] - stateOrder[b.computedState];
      }
      
      const startA = new Date(a.startTime).getTime();
      const startB = new Date(b.startTime).getTime();
      
      if (a.computedState === 'active') {
        // Active events: end sooner first
        return new Date(a.endTime).getTime() - new Date(b.endTime).getTime();
      } else if (a.computedState === 'upcoming') {
        // Upcoming: start sooner first
        return startA - startB;
      } else {
        // Past: ended more recently first
        return new Date(b.endTime).getTime() - new Date(a.endTime).getTime();
      }
    });
  }

  function getEventState(evt, referenceDate) {
    const start = new Date(evt.startTime);
    const end = new Date(evt.endTime);
    
    if (referenceDate >= start && referenceDate < end) {
      return 'active';
    } else if (referenceDate < start) {
      return 'upcoming';
    } else {
      return 'past';
    }
  }

  function setFilter(filterType) {
    activeFilter = filterType;
    
    // Update active class on buttons
    Object.keys(filterBtns).forEach(key => {
      if (filterBtns[key]) {
        if (key === filterType) {
          filterBtns[key].classList.add('active');
        } else {
          filterBtns[key].classList.remove('active');
        }
      }
    });

    renderEvents();
  }

  function renderEvents() {
    // Clear previous dynamic cards (keep loader & empty state in DOM)
    const cards = eventsGrid.querySelectorAll('.event-card');
    cards.forEach(c => c.remove());

    const filtered = allEvents.filter(evt => {
      if (activeFilter === 'all') return true;
      return evt.computedState === activeFilter;
    });

    showLoader(false);

    if (filtered.length === 0) {
      showEmptyState(true);
      return;
    }

    showEmptyState(false);

    filtered.forEach((evt, idx) => {
      const cardEl = createEventCard(evt, idx);
      eventsGrid.appendChild(cardEl);
    });
  }

  function createEventCard(evt, index) {
    const card = document.createElement('article');
    card.className = `event-card ${evt.computedState}-state`;
    card.style.animationDelay = `${index * 0.05}s`;
    
    // Date formats
    const startDisplay = formatEventTime(evt.startTime, evt.timingType);
    const endDisplay = formatEventTime(evt.endTime, evt.timingType);

    // State Badge text
    let badgeClass = 'past-badge';
    let badgeText = 'ARCHIVED';
    if (evt.computedState === 'active') {
      badgeClass = 'active-badge';
      badgeText = 'ACTIVE NOW';
    } else if (evt.computedState === 'upcoming') {
      badgeClass = 'upcoming-badge';
      badgeText = 'SCHEDULED';
    }

    // Changes elements list
    const changesItems = evt.changes.map(ch => `<li>${escapeHtml(ch)}</li>`).join('');

    card.innerHTML = `
      <div class="card-header">
        <h2 class="card-title">${escapeHtml(evt.name)}</h2>
        <span class="badge ${badgeClass}">${badgeText}</span>
      </div>
      
      <div class="card-time ${evt.timingType === 'local' ? 'local-time-border' : ''}">
        <div class="time-row">
          <span class="time-lbl">START:</span>
          <span class="time-val">${startDisplay}</span>
        </div>
        <div class="time-row">
          <span class="time-lbl">END:</span>
          <span class="time-val">${endDisplay}</span>
        </div>
      </div>
      
      <div class="card-changes">
        <h3 class="changes-title">GAMEPLAY_MUTATIONS</h3>
        <ul class="changes-list">
          ${changesItems || '<li>No specific gameplay mutations detected.</li>'}
        </ul>
      </div>
      
      <div class="card-footer">
        <span class="source-intel">SOURCE: <a class="source-link" href="${evt.articleUrl}" target="_blank" rel="noopener">${escapeHtml(evt.articleTitle)}</a></span>
      </div>
    `;

    return card;
  }

  // Format time based on global (UTC converted) vs local (wall clock displayed literally)
  function formatEventTime(timeIsoString, timingType) {
    const date = new Date(timeIsoString);
    
    if (timingType === 'local') {
      // Display wall clock time as input in UTC, treating it as floating local time.
      // We extract the date fields directly from the UTC representation to show the floating time.
      const year = date.getUTCFullYear();
      const month = String(date.getUTCMonth() + 1).padStart(2, '0');
      const day = String(date.getUTCDate()).padStart(2, '0');
      const hours = String(date.getUTCHours()).padStart(2, '0');
      const minutes = String(date.getUTCMinutes()).padStart(2, '0');
      
      return `${year}-${month}-${day} ${hours}:${minutes} LOCAL`;
    } else {
      // Global: convert to user system local time
      const year = date.getFullYear();
      const month = String(date.getMonth() + 1).padStart(2, '0');
      const day = String(date.getDate()).padStart(2, '0');
      const hours = String(date.getHours()).padStart(2, '0');
      const minutes = String(date.getMinutes()).padStart(2, '0');
      
      return `${year}-${month}-${day} ${hours}:${minutes}`;
    }
  }

  function updateStatusPanel() {
    const activeCount = allEvents.filter(e => e.computedState === 'active').length;
    dbCountDisplay.textContent = `${allEvents.length} UNITS`;

    if (activeCount > 0) {
      statusNode.className = 'xm-node anomaly';
      statusText.textContent = 'ANOMALY DETECTED';
      statusText.style.color = '#ff2a6d';
    } else {
      statusNode.className = 'xm-node';
      statusText.textContent = 'MONITORING';
      statusText.style.color = '#02ff77';
    }
  }

  function showLoader(visible) {
    if (visible) {
      loader.classList.remove('hidden');
    } else {
      loader.classList.add('hidden');
    }
  }

  function showEmptyState(visible) {
    if (visible) {
      emptyState.classList.remove('hidden');
    } else {
      emptyState.classList.add('hidden');
    }
  }

  function escapeHtml(str) {
    return str
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }
});
