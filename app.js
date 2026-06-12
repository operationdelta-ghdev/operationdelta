/* ----------------------------------------------------
   Ingress Scanner Event Console Controller (Vanilla JS)
   ---------------------------------------------------- */

document.addEventListener('DOMContentLoaded', () => {
  // Constants & State
  const EVENTS_DATA_URL = 'events.json';
  let allEvents = [];
  let activeFilter = 'all';
  let trackerInterval = null;
  let clickedCardId = null;
  let activeClickTimeout = null;

  // DOM Elements
  const eventsGrid = document.getElementById('events-grid');
  const loader = document.getElementById('loader');
  const emptyState = document.getElementById('empty-state');
  const statusNode = document.getElementById('status-node');
  const lastUpdatedEl = document.getElementById('last-updated');
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
      const articles = await response.json();
      
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

      // Render Dashboard Grid & Calendar view
      renderEvents();
      renderCalendar();
      updateStatusPanel();

      // Display the datestamp of the latest parsed data
      if (articles && articles.length > 0) {
        let latestTimestamp = 0;
        articles.forEach(art => {
          if (art.published_at > latestTimestamp) {
            latestTimestamp = art.published_at;
          }
        });
        if (latestTimestamp > 0) {
          const lastUpdatedDate = new Date(latestTimestamp);
          const year = lastUpdatedDate.getFullYear();
          const month = String(lastUpdatedDate.getMonth() + 1).padStart(2, '0');
          const day = String(lastUpdatedDate.getDate()).padStart(2, '0');
          const lastUpdatedStr = `${year}-${month}-${day}`;
          if (lastUpdatedEl) {
            lastUpdatedEl.textContent = lastUpdatedStr;
          }
        }
      }

      // Start Countdown Ticker
      if (!trackerInterval) {
        trackerInterval = setInterval(updateTrackers, 1000);
        updateTrackers();
      }

    } catch (error) {
      console.error('Failed to load Ingress events data:', error);
      showLoader(false);
      showEmptyState(true);
      if (lastUpdatedEl) {
        lastUpdatedEl.textContent = 'LINK ERROR';
        lastUpdatedEl.style.color = '#ff2a6d';
      }
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

  // Calculate event status: active, upcoming, past
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
    const cards = eventsGrid.querySelectorAll('.event-card, .expand-container');
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

    let pastCount = 0;
    const pastCardsToHide = [];

    filtered.forEach((evt) => {
      let isHiddenArchived = false;
      if (evt.computedState === 'past') {
        pastCount++;
        if (pastCount > 3) {
          isHiddenArchived = true;
        }
      }

      const cardEl = createEventCard(evt, isHiddenArchived);
      eventsGrid.appendChild(cardEl);
      
      if (isHiddenArchived) {
        pastCardsToHide.push(cardEl);
      }
    });

    // If there are more than 3 archived/past events, render the Expand Button
    if (pastCount > 3) {
      const expandContainer = document.createElement('div');
      expandContainer.className = 'expand-container';
      expandContainer.id = 'expand-archived-container';
      
      const expandBtn = document.createElement('button');
      expandBtn.id = 'expand-archived-btn';
      expandBtn.className = 'expand-btn';
      expandBtn.textContent = `SHOW ALL ARCHIVED (+${pastCount - 3})`;
      
      let isExpanded = false;
      expandBtn.addEventListener('click', () => {
        isExpanded = !isExpanded;
        pastCardsToHide.forEach(card => {
          if (isExpanded) {
            card.classList.remove('hidden-archived');
          } else {
            card.classList.add('hidden-archived');
          }
        });
        expandBtn.textContent = isExpanded ? 'COLLAPSE ARCHIVED' : `SHOW ALL ARCHIVED (+${pastCount - 3})`;
      });

      expandContainer.appendChild(expandBtn);
      eventsGrid.appendChild(expandContainer);
    }
  }

  function createEventCard(evt, isHiddenArchived) {
    const card = document.createElement('article');
    card.className = `event-card ${evt.computedState}-state`;
    if (isHiddenArchived) {
      card.classList.add('hidden-archived');
    }
    card.id = `card-${evt.articleId}-${evt.name.replace(/\s+/g, '-').toLowerCase()}`;
    
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

    // Tracker markup for live countdowns
    let trackerMarkup = '';
    if (evt.computedState === 'active' || evt.computedState === 'upcoming') {
      const trackerId = `tracker-${evt.articleId}-${evt.name.replace(/\s+/g, '-').toLowerCase()}`;
      trackerMarkup = `
        <div class="event-tracker ${evt.computedState === 'active' ? 'tracker-active' : 'tracker-upcoming'}" id="${trackerId}">
          <span class="tracker-icon"></span>
          <span class="tracker-text">SYNCHRONIZING TIMELINE...</span>
        </div>
      `;
    }

    // Changes elements list
    const changesItems = evt.changes.map(ch => `<li>${escapeHtml(ch)}</li>`).join('');

    card.innerHTML = `
      <div class="card-header">
        <h2 class="card-title">${escapeHtml(evt.name)}</h2>
        <span class="badge ${badgeClass}">${badgeText}</span>
      </div>
      
      ${trackerMarkup}
      
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
      const year = date.getUTCFullYear();
      const month = String(date.getUTCMonth() + 1).padStart(2, '0');
      const day = String(date.getUTCDate()).padStart(2, '0');
      const hours = String(date.getUTCHours()).padStart(2, '0');
      const minutes = String(date.getUTCMinutes()).padStart(2, '0');
      
      return `${year}-${month}-${day} ${hours}:${minutes} LOCAL`;
    } else {
      const year = date.getFullYear();
      const month = String(date.getMonth() + 1).padStart(2, '0');
      const day = String(date.getDate()).padStart(2, '0');
      const hours = String(date.getHours()).padStart(2, '0');
      const minutes = String(date.getMinutes()).padStart(2, '0');
      
      return `${year}-${month}-${day} ${hours}:${minutes}`;
    }
  }

  // Render horizontal 28-day timeline calendar above filter navigation
  function renderCalendar() {
    const calWeeks = document.getElementById('cal-weeks');
    const calDays = document.getElementById('cal-days');
    const calTimeline = document.getElementById('cal-timeline');
    
    if (!calWeeks || !calDays || !calTimeline) return;
    
    calWeeks.innerHTML = '';
    calDays.innerHTML = '';
    calTimeline.innerHTML = '';
    
    const now = new Date();
    
    // Start of current week (Sunday)
    const currentWeekStart = new Date(now);
    currentWeekStart.setDate(now.getDate() - now.getDay());
    currentWeekStart.setHours(0,0,0,0);
    
    // Calendar start date (Sunday of last week)
    const calStart = new Date(currentWeekStart);
    calStart.setDate(currentWeekStart.getDate() - 7);
    
    // Calendar end date (Saturday of two weeks out, i.e., 28 days total)
    const calEnd = new Date(calStart);
    calEnd.setDate(calStart.getDate() + 28);
    
    const calStartMs = calStart.getTime();
    const calEndMs = calEnd.getTime();

    // Render Weeks header labels
    const weekLabels = ["LAST WEEK", "CURRENT WEEK", "UPCOMING WEEK +1", "UPCOMING WEEK +2"];
    for (let w = 0; w < 4; w++) {
      const weekEl = document.createElement('div');
      weekEl.className = 'cal-week-lbl';
      if (w === 1) {
        weekEl.classList.add('current-week-lbl');
      } else if (w > 1) {
        weekEl.classList.add('upcoming-week-lbl');
      }
      weekEl.textContent = weekLabels[w];
      calWeeks.appendChild(weekEl);
    }
    
    // Render 28 Days headers
    const dayNames = ["S", "M", "T", "W", "T", "F", "S"];
    for (let d = 0; d < 28; d++) {
      const dayDate = new Date(calStart);
      dayDate.setDate(calStart.getDate() + d);
      
      const dayCell = document.createElement('div');
      dayCell.className = 'cal-day-cell';
      
      const isToday = dayDate.toDateString() === now.toDateString();
      if (isToday) {
        dayCell.classList.add('today-cell');
      }
      
      dayCell.innerHTML = `
        <span class="day-name">${dayNames[dayDate.getDay()]}</span>
        <span class="day-num">${dayDate.getDate()}</span>
      `;
      calDays.appendChild(dayCell);
    }
    
    // Filter events overlapping with 28-day window
    const timelineEvents = allEvents.filter(evt => {
      const startMs = new Date(evt.startTime).getTime();
      const endMs = new Date(evt.endTime).getTime();
      return startMs < calEndMs && endMs > calStartMs;
    });

    if (timelineEvents.length === 0) {
      const emptyRow = document.createElement('div');
      emptyRow.style.textAlign = 'center';
      emptyRow.style.padding = '1rem';
      emptyRow.style.fontFamily = 'var(--font-sci-fi)';
      emptyRow.style.fontSize = '0.75rem';
      emptyRow.style.color = 'var(--color-text-muted)';
      emptyRow.textContent = 'NO ACTIVE OR SCHEDULED EVENTS IN THIS RANGE';
      calTimeline.appendChild(emptyRow);
      return;
    }

    // Render rows with positioned bars using CSS Grid
    timelineEvents.forEach(evt => {
      const row = document.createElement('div');
      row.className = 'calendar-row';
      
      const startMs = new Date(evt.startTime).getTime();
      const endMs = new Date(evt.endTime).getTime();
      
      const overlapStart = Math.max(startMs, calStartMs);
      const overlapEnd = Math.min(endMs, calEndMs);
      
      const startDayIdx = Math.floor((overlapStart - calStartMs) / (1000 * 60 * 60 * 24));
      const endDayIdx = Math.floor((overlapEnd - calStartMs) / (1000 * 60 * 60 * 24));
      
      const gridColStart = startDayIdx + 1;
      const gridColEnd = endDayIdx + 2; 

      let barStateClass = 'cal-bar-past';
      if (evt.computedState === 'active') {
        barStateClass = 'cal-bar-active';
      } else if (evt.computedState === 'upcoming') {
        barStateClass = 'cal-bar-upcoming';
      }
      
      const bar = document.createElement('div');
      bar.className = `cal-bar ${barStateClass}`;
      bar.style.gridColumnStart = gridColStart;
      bar.style.gridColumnEnd = gridColEnd;
      bar.textContent = evt.name;
      bar.title = `${evt.name} (${formatEventTime(evt.startTime, evt.timingType)} - ${formatEventTime(evt.endTime, evt.timingType)})`;
      
      // Tap/Hover highlight card interaction
      const cardId = `card-${evt.articleId}-${evt.name.replace(/\s+/g, '-').toLowerCase()}`;
      
      const highlightCard = (shouldScroll) => {
        const card = document.getElementById(cardId);
        if (card) {
          const wasHidden = card.classList.contains('hidden-archived');
          if (wasHidden) {
            card.classList.remove('hidden-archived');
            card.classList.add('temp-visible');
          }
          
          if (shouldScroll) {
            card.scrollIntoView({ behavior: 'smooth', block: 'center' });
            
            // Handle click state: keep highlighted/visible for 2.5 seconds
            if (activeClickTimeout) {
              clearTimeout(activeClickTimeout);
            }
            if (clickedCardId && clickedCardId !== cardId) {
              // Reset previous clicked card immediately
              const prevCard = document.getElementById(clickedCardId);
              if (prevCard) {
                prevCard.classList.remove('highlight-pulse');
                if (prevCard.classList.contains('temp-visible')) {
                  prevCard.classList.remove('temp-visible');
                  const expandBtn = document.getElementById('expand-archived-btn');
                  if (expandBtn && expandBtn.textContent.includes('SHOW ALL')) {
                    prevCard.classList.add('hidden-archived');
                  }
                }
              }
            }
            clickedCardId = cardId;
            activeClickTimeout = setTimeout(() => {
              clickedCardId = null;
              unhighlightCard();
            }, 2500);
          }
          
          card.classList.remove('highlight-pulse');
          void card.offsetWidth; // force reflow
          card.classList.add('highlight-pulse');
        }
      };

      const unhighlightCard = () => {
        // If this card is currently clicked and under its 2.5s timer, do not remove hover highlight
        if (clickedCardId === cardId) {
          return;
        }
        const card = document.getElementById(cardId);
        if (card) {
          card.classList.remove('highlight-pulse');
          if (card.classList.contains('temp-visible')) {
            card.classList.remove('temp-visible');
            const expandBtn = document.getElementById('expand-archived-btn');
            if (expandBtn && expandBtn.textContent.includes('SHOW ALL')) {
              card.classList.add('hidden-archived');
            }
          }
        }
      };

      bar.addEventListener('click', () => highlightCard(true));
      bar.addEventListener('mouseenter', () => highlightCard(false));
      bar.addEventListener('mouseleave', unhighlightCard);
      
      row.appendChild(bar);
      calTimeline.appendChild(row);
    });
  }

  // Update event tickers live every second
  function updateTrackers() {
    const now = new Date();
    let stateChanged = false;
    
    allEvents.forEach(evt => {
      if (evt.computedState === 'active' || evt.computedState === 'upcoming') {
        const trackerId = `tracker-${evt.articleId}-${evt.name.replace(/\s+/g, '-').toLowerCase()}`;
        const trackerEl = document.getElementById(trackerId);
        if (!trackerEl) return;
        
        const textEl = trackerEl.querySelector('.tracker-text');
        if (!textEl) return;
        
        let diffMs = 0;
        let prefix = '';
        
        if (evt.computedState === 'active') {
          const endTime = new Date(evt.endTime);
          diffMs = endTime.getTime() - now.getTime();
          prefix = 'REMAINING: ';
        } else {
          const startTime = new Date(evt.startTime);
          diffMs = startTime.getTime() - now.getTime();
          prefix = 'STARTS IN: ';
        }
        
        if (diffMs <= 0) {
          textEl.textContent = evt.computedState === 'active' ? 'MUTATION COMPLETE' : 'MUTATION ACTIVE';
          stateChanged = true;
          return;
        }
        
        const seconds = Math.floor((diffMs / 1000) % 60);
        const minutes = Math.floor((diffMs / (1000 * 60)) % 60);
        const hours = Math.floor((diffMs / (1000 * 60 * 60)) % 24);
        const days = Math.floor(diffMs / (1000 * 60 * 60 * 24));
        
        let timeStr = '';
        if (days > 0) {
          timeStr += `${days}D `;
        }
        if (days > 0 || hours > 0) {
          timeStr += `${hours}H `;
        }
        if (days > 0 || hours > 0 || minutes > 0) {
          timeStr += `${String(minutes).padStart(2, '0')}M `;
        }
        timeStr += `${String(seconds).padStart(2, '0')}S`;
        
        textEl.textContent = prefix + timeStr;
      }
    });

    if (stateChanged) {
      sortEvents();
      renderEvents();
      renderCalendar();
      updateStatusPanel();
    }
  }

  function updateStatusPanel() {
    const activeCount = allEvents.filter(e => e.computedState === 'active').length;
    dbCountDisplay.textContent = `${allEvents.length} UNITS`;

    if (activeCount > 0) {
      statusNode.className = 'xm-node anomaly';
    } else {
      statusNode.className = 'xm-node';
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
