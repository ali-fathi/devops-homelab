document.addEventListener("DOMContentLoaded", () => {
    // Navigation Tabs
    const tabBtns = document.querySelectorAll(".tab-btn");
    const tabPanes = document.querySelectorAll(".tab-pane");

    tabBtns.forEach(btn => {
        btn.addEventListener("click", () => {
            const targetTab = btn.getAttribute("data-tab");
            
            tabBtns.forEach(b => b.classList.remove("active"));
            tabPanes.forEach(p => p.classList.remove("active"));

            btn.classList.add("active");
            document.getElementById(targetTab).classList.add("active");
        });
    });

    // Build a rolling list of real calendar months instead of hard-coded dates.
    const reportMonthSelect = document.getElementById("report-month");
    populateMonthSelector(reportMonthSelect);
    if (reportMonthSelect) {
        reportMonthSelect.addEventListener("change", () => {
            fetchHealthData(reportMonthSelect.value);
        });
    }

    // Export buttons
    document.getElementById("btn-export-csv").addEventListener("click", () => {
        const month = reportMonthSelect.value;
        window.location.href = `/api/report/export?format=csv&month=${month}`;
    });

    document.getElementById("btn-export-json").addEventListener("click", () => {
        const month = reportMonthSelect.value;
        window.location.href = `/api/report/export?format=json&month=${month}`;
    });

    document.getElementById("btn-download-pdf").addEventListener("click", () => {
        const month = reportMonthSelect.value;
        window.location.href = `/api/report/download?month=${month}`;
    });

    document.getElementById("btn-regenerate").addEventListener("click", () => {
        const month = reportMonthSelect.value;
        const btn = document.getElementById("btn-regenerate");
        btn.disabled = true;
        btn.innerHTML = "⏳ Regenerating...";
        
        fetch(`/api/report/regenerate?month=${month}`, { method: "POST" })
            .then(res => {
                if (res.status === 401) {
                    window.location.href = "/login";
                    throw new Error("Authentication required");
                }
                return res.json();
            })
            .then(data => {
                btn.disabled = false;
                btn.innerHTML = "🔄 Regenerate Report";
                if (data.status === "ok") {
                    fetchHealthData(month);
                } else {
                    alert("Failed to regenerate report: " + data.message);
                }
            })
            .catch(err => {
                btn.disabled = false;
                btn.innerHTML = "🔄 Regenerate Report";
                console.error("Error regenerating report:", err);
            });
    });

    // Initial load
    if (reportMonthSelect && reportMonthSelect.value) {
        fetchHealthData(reportMonthSelect.value);
    }
});

let recoveryChart = null;
let sleepChart = null;
let hrvChart = null;

function populateMonthSelector(select) {
    if (!select) return;

    const now = new Date();
    for (let offset = 0; offset < 12; offset += 1) {
        const date = new Date(now.getFullYear(), now.getMonth() - offset, 1);
        const value = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
        const label = date.toLocaleDateString(undefined, { year: "numeric", month: "long" });
        const option = document.createElement("option");
        option.value = value;
        option.textContent = label;
        select.appendChild(option);
    }
}

function fetchHealthData(month) {
    const statusText = document.getElementById("connection-status-text");
    const statusDot = document.getElementById("connection-status-dot");

    fetch(`/api/health?month=${encodeURIComponent(month)}`)
        .then(async res => {
            if (res.status === 401) {
                window.location.href = "/login";
                throw new Error("Authentication required");
            }
            const data = await res.json();
            if (!res.ok) {
                throw new Error(data.error || `Health API returned ${res.status}`);
            }
            return data;
        })
        .then(data => {
            if (data.mocked) {
                statusText.innerText = "Demo / Mock Mode";
                statusDot.className = "status-dot mock";
            } else if (data.status === "no_data") {
                statusText.innerText = "Connected - No Measurements";
                statusDot.className = "status-dot mock";
            } else {
                statusText.innerText = "Connected to Homelab Databases";
                statusDot.className = "status-dot";
            }

            populateCommandCenter(data.daily || {});
            populateWeeklyHealth(data.weekly || {});
            populateMonthlyReport(data.monthly || {});
            renderCharts(data.charts || { labels: [], recovery: [], sleep_duration: [], sleep_score: [], hrv: [], resting_hr: [] });
        })
        .catch(err => {
            console.error("Error fetching health metrics:", err);
            statusText.innerText = `Data Unavailable: ${err.message}`;
            statusDot.className = "status-dot red";
            populateCommandCenter({});
        });
}

function populateCommandCenter(daily) {
    daily = daily || {};

    // Current Recovery/Readiness
    document.getElementById("recovery-score").innerText = daily.recovery_score ?? "N/A";
    document.getElementById("recovery-change").innerHTML = formatChange(daily.recovery_change);
    
    // Heart Rate / Resting HR
    document.getElementById("heart-rate").innerText = `${daily.current_hr ?? "N/A"} / ${daily.resting_hr ?? "N/A"}`;
    document.getElementById("hr-change").innerHTML = formatChange(daily.hr_change);
    
    // HRV
    document.getElementById("hrv-value").innerText = daily.hrv ?? "N/A";
    document.getElementById("hrv-change").innerHTML = formatChange(daily.hrv_change);

    // Sleep
    document.getElementById("sleep-value").innerText = daily.sleep_duration ?? "N/A";
    document.getElementById("sleep-quality").innerText = daily.sleep_quality ? `(${daily.sleep_quality})` : "";
    document.getElementById("sleep-change").innerHTML = formatChange(daily.sleep_change);

    // Stress & SpO2
    document.getElementById("stress-value").innerText = daily.stress ?? "N/A";
    document.getElementById("spo2-value").innerText = daily.spo2 ? `${daily.spo2}%` : "N/A";

    // Activity Metrics
    document.getElementById("steps-value").innerText = daily.steps != null ? daily.steps.toLocaleString() : "N/A";
    document.getElementById("calories-value").innerText = daily.calories ?? "N/A";
    document.getElementById("distance-value").innerText = daily.distance != null ? `${daily.distance} km` : "N/A";
    document.getElementById("active-min").innerText = daily.active_minutes ?? "N/A";

    // Battery / Last Sync
    document.getElementById("ring-battery").innerText = daily.ring_battery != null ? `${daily.ring_battery}%` : "N/A";
    document.getElementById("ring-sync").innerText = daily.last_sync || "N/A";

    // Garmin Workouts
    const workoutsList = document.getElementById("workouts-list");
    workoutsList.innerHTML = "";
    if (daily.workouts && daily.workouts.length > 0) {
        daily.workouts.forEach(w => {
            const item = document.createElement("div");
            item.className = "activity-item";
            item.innerHTML = `
                <div class="activity-item-left">
                    <span class="activity-badge ${escapeHtml(String(w.type || "workout").toLowerCase())}">${escapeHtml(w.type || "Workout")}</span>
                    <div>
                        <div><strong>${escapeHtml(w.name || "Workout")}</strong></div>
                        <div class="activity-details">${escapeHtml(w.duration ?? 0)} min | ${escapeHtml(w.calories ?? 0)} kcal ${w.distance != null ? `| ${escapeHtml(w.distance)} km` : ""}</div>
                    </div>
                </div>
                <div class="activity-details">${escapeHtml(w.time || "")}</div>
            `;
            workoutsList.appendChild(item);
        });
    } else {
        workoutsList.innerHTML = "<div class='activity-details' style='padding: 1rem; text-align: center;'>No recent workouts logged.</div>";
    }
}

function populateWeeklyHealth(weekly) {
    // Score circle
    document.getElementById("weekly-score-num").innerText = weekly.score || "N/A";
    document.getElementById("weekly-score-label").innerText = weekly.evaluation || "Average";

    // Narrative content
    document.getElementById("weekly-sleep-insights").innerHTML = `<p>${weekly.sleep_insights || "No sleep data collected this week."}</p>`;
    document.getElementById("weekly-recovery-trend").innerHTML = `<p>${weekly.recovery_insights || "No recovery trend calculated yet."}</p>`;
    document.getElementById("weekly-workout-summary").innerHTML = `<p>${weekly.workout_insights || "No workouts logged this week."}</p>`;
    document.getElementById("weekly-stress-observations").innerHTML = `<p>${weekly.stress_insights || "Stress averages are within normal ranges."}</p>`;
    document.getElementById("weekly-records").innerHTML = `<p>${weekly.achievements || "None logged yet."}</p>`;
    document.getElementById("weekly-suggestions").innerHTML = `<p>${weekly.focus || "Continue keeping up with active routines!"}</p>`;
}

function populateMonthlyReport(monthly) {
    // Top Insights
    document.getElementById("monthly-insights-list").innerHTML = `
        <div class="narrative-section">
            <h3>📈 Key Trends</h3>
            <p>${monthly.trends_summary}</p>
        </div>
        <div class="narrative-section">
            <h3>🎯 Month Goals</h3>
            <p>${monthly.suggested_goals}</p>
        </div>
    `;

    // Monthly data metrics comparison table
    const tableBody = document.getElementById("monthly-comparison-table-body");
    tableBody.innerHTML = "";
    if (monthly.metrics && monthly.metrics.length > 0) {
        monthly.metrics.forEach(m => {
            const tr = document.createElement("tr");
            tr.innerHTML = `
                <td><strong>${m.name}</strong></td>
                <td>${m.current}</td>
                <td>${m.previous}</td>
                <td>
                    ${m.diff}
                    <span class="trend-arrow ${m.direction}">${m.direction === 'up' ? '▲' : m.direction === 'down' ? '▼' : '■'}</span>
                </td>
            `;
            tableBody.appendChild(tr);
        });
    }
}

function renderCharts(charts) {
    const ctx1 = document.getElementById("recoveryTrendChart").getContext("2d");
    const ctx2 = document.getElementById("sleepQualityChart").getContext("2d");
    const ctx3 = document.getElementById("hrvHrvTrendChart").getContext("2d");

    // Destroy existing charts if they exist to prevent hover redraw bugs
    if (recoveryChart) recoveryChart.destroy();
    if (sleepChart) sleepChart.destroy();
    if (hrvChart) hrvChart.destroy();

    // 1. Recovery Trend Chart
    recoveryChart = new Chart(ctx1, {
        type: 'line',
        data: {
            labels: charts.labels,
            datasets: [{
                label: 'Readiness / Recovery Score',
                data: charts.recovery,
                borderColor: '#3b82f6',
                backgroundColor: 'rgba(59, 130, 246, 0.1)',
                borderWidth: 3,
                tension: 0.35,
                fill: true,
                pointBackgroundColor: '#3b82f6'
            }]
        },
        options: getChartOptions('Readiness Score Over Time', [0, 100])
    });

    // 2. Sleep Duration vs Quality
    sleepChart = new Chart(ctx2, {
        type: 'bar',
        data: {
            labels: charts.labels,
            datasets: [
                {
                    type: 'bar',
                    label: 'Sleep Duration (hrs)',
                    data: charts.sleep_duration,
                    backgroundColor: 'rgba(139, 92, 246, 0.65)',
                    borderColor: '#8b5cf6',
                    borderWidth: 1,
                    yAxisID: 'y'
                },
                {
                    type: 'line',
                    label: 'Sleep Score',
                    data: charts.sleep_score,
                    borderColor: '#10b981',
                    borderWidth: 3,
                    tension: 0.3,
                    pointBackgroundColor: '#10b981',
                    yAxisID: 'y1'
                }
            ]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: { labels: { color: '#9ca3af', font: { family: 'Outfit' } } }
            },
            scales: {
                x: { grid: { color: 'rgba(255, 255, 255, 0.05)' }, ticks: { color: '#9ca3af', font: { family: 'Outfit' } } },
                y: { 
                    type: 'linear',
                    display: true,
                    position: 'left',
                    grid: { color: 'rgba(255, 255, 255, 0.05)' },
                    ticks: { color: '#9ca3af', font: { family: 'Outfit' } },
                    title: { display: true, text: 'Hours', color: '#9ca3af' }
                },
                y1: {
                    type: 'linear',
                    display: true,
                    position: 'right',
                    grid: { drawOnChartArea: false },
                    ticks: { color: '#9ca3af', font: { family: 'Outfit' } },
                    title: { display: true, text: 'Score', color: '#9ca3af' },
                    min: 0,
                    max: 100
                }
            }
        }
    });

    // 3. HRV and Resting Heart Rate Trend
    hrvChart = new Chart(ctx3, {
        type: 'line',
        data: {
            labels: charts.labels,
            datasets: [
                {
                    label: 'HRV (ms)',
                    data: charts.hrv,
                    borderColor: '#10b981',
                    borderWidth: 2,
                    tension: 0.3,
                    pointBackgroundColor: '#10b981',
                    fill: false
                },
                {
                    label: 'Resting HR (bpm)',
                    data: charts.resting_hr,
                    borderColor: '#ef4444',
                    borderWidth: 2,
                    tension: 0.3,
                    pointBackgroundColor: '#ef4444',
                    fill: false
                }
            ]
        },
        options: getChartOptions('HRV & Resting Heart Rate', [30, 120])
    });
}

function getChartOptions(titleText, suggestedRange) {
    return {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
            legend: { labels: { color: '#9ca3af', font: { family: 'Outfit' } } }
        },
        scales: {
            x: { grid: { color: 'rgba(255, 255, 255, 0.05)' }, ticks: { color: '#9ca3af', font: { family: 'Outfit' } } },
            y: { 
                grid: { color: 'rgba(255, 255, 255, 0.05)' }, 
                ticks: { color: '#9ca3af', font: { family: 'Outfit' } },
                suggestedMin: suggestedRange[0],
                suggestedMax: suggestedRange[1]
            }
        }
    };
}

function escapeHtml(value) {
    return String(value)
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;")
        .replaceAll("'", "&#039;");
}

function formatChange(val) {
    if (val === undefined || val === null || val === 0) {
        return `<span class="metric-change neutral">--</span>`;
    }
    const cleanVal = Number(val);
    if (cleanVal > 0) {
        return `<span class="metric-change up">▲ +${cleanVal.toFixed(0)}</span>`;
    } else {
        return `<span class="metric-change down">▼ ${cleanVal.toFixed(0)}</span>`;
    }
}
