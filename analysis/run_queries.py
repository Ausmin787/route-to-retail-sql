"""
Python analytics layer — runs Q6, Q9, Q14 against Neon PostgreSQL and produces charts.

Prerequisites:
    pip install psycopg2-binary pandas matplotlib python-dotenv

Setup:
    Create a .env file in the project root:
        DATABASE_URL=postgresql://<user>:<password>@<neon-host>/neondb?sslmode=require

Usage:
    python analysis/run_queries.py
    Outputs: CSVs to outputs/, charts (PNG) to visuals/
"""

import os
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from dotenv import load_dotenv

load_dotenv()

DATABASE_URL = os.environ.get("DATABASE_URL")
if not DATABASE_URL:
    raise EnvironmentError("DATABASE_URL not set. Create a .env file in the project root.")

import psycopg2

os.makedirs("outputs", exist_ok=True)
os.makedirs("visuals", exist_ok=True)


def query(sql: str) -> pd.DataFrame:
    conn = psycopg2.connect(DATABASE_URL)
    df = pd.read_sql_query(sql, conn)
    conn.close()
    return df


# fmt: off
POSITIVE_COLOR = "#2ecc71"
NEGATIVE_COLOR = "#e74c3c"
LINE_COLOR     = "#3498db"
BAR_COLORS     = ["#3498db", "#e74c3c", "#2ecc71", "#f39c12",
                  "#9b59b6", "#1abc9c", "#e67e22", "#34495e"]
# fmt: on


def clean_ax(ax):
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.set_facecolor("white")


# ── Q6: Monthly revenue trend ─────────────────────────────────────────────────

Q6_SQL = """
SELECT
    DATE_TRUNC('month', so.order_date)::date AS sales_month,
    ROUND(SUM(soi.net_sales_value), 2)       AS monthly_revenue
FROM sales_orders so
JOIN sales_order_items soi ON so.order_id = soi.order_id
WHERE so.order_date >= DATE '2025-01-01'
  AND so.order_date < DATE '2026-01-01'
GROUP BY DATE_TRUNC('month', so.order_date)
ORDER BY sales_month;
"""

print("Running Q6...")
q6 = query(Q6_SQL)
q6.to_csv("outputs/q6_monthly_revenue.csv", index=False)

fig, ax = plt.subplots(figsize=(12, 6))
fig.patch.set_facecolor("white")
clean_ax(ax)

months_str = q6["sales_month"].astype(str).str[:7]
ax.plot(months_str, q6["monthly_revenue"], color=LINE_COLOR, linewidth=2.5, marker="o", markersize=6)
ax.fill_between(months_str, q6["monthly_revenue"], alpha=0.12, color=LINE_COLOR)

# Annotate festive peak (Sep–Nov)
for i, (m, rev) in enumerate(zip(months_str, q6["monthly_revenue"])):
    if m in [str(q6["sales_month"].max())[:7]] or rev == q6["monthly_revenue"].max():
        ax.annotate(f"₹{rev/100000:.1f}L", (m, rev), textcoords="offset points",
                    xytext=(0, 10), ha="center", fontsize=9, fontweight="bold", color="#2c3e50")

ax.set_title("Monthly Revenue Trend — Festive Peak Visible Sep–Nov",
             fontsize=14, fontweight="bold", color="#2c3e50", pad=14)
ax.set_xlabel("Month", fontsize=11)
ax.set_ylabel("Net Revenue (₹)", fontsize=11)
ax.yaxis.set_major_formatter(plt.FuncFormatter(lambda x, _: f"₹{x/100000:.1f}L"))
ax.tick_params(axis="x", rotation=45)
plt.tight_layout()
plt.savefig("visuals/q6_monthly_revenue.png", dpi=150, bbox_inches="tight", facecolor="white")
plt.close()
print("  Saved: visuals/q6_monthly_revenue.png")


# ── Q9: Promotion performance ─────────────────────────────────────────────────

Q9_SQL = """
SELECT
    pr.promotion_name,
    pr.category,
    pr.discount_percent,
    ROUND(SUM(soi.net_sales_value), 2)    AS net_revenue,
    ROUND(SUM(soi.discount_value), 2)     AS total_discount,
    ROUND(SUM(soi.discount_value) * 100.0
          / SUM(soi.gross_sales_value), 2) AS effective_discount_pct
FROM promotions pr
JOIN sales_order_items soi ON pr.promotion_id = soi.promotion_id
JOIN sales_orders so       ON soi.order_id    = so.order_id
WHERE so.order_date >= DATE '2025-01-01'
  AND so.order_date < DATE '2026-01-01'
GROUP BY pr.promotion_id, pr.promotion_name, pr.category, pr.discount_percent
ORDER BY net_revenue DESC;
"""

print("Running Q9...")
q9 = query(Q9_SQL)
q9.to_csv("outputs/q9_promotion_performance.csv", index=False)

fig, ax = plt.subplots(figsize=(13, 6))
fig.patch.set_facecolor("white")
clean_ax(ax)

import numpy as np
x = np.arange(len(q9))
w = 0.35
bars1 = ax.bar(x - w / 2, q9["net_revenue"] / 100000, w,
               color=LINE_COLOR, edgecolor="white", linewidth=1.2, label="Net Revenue (₹L)")
ax2 = ax.twinax() if hasattr(ax, "twinax") else ax.twinx()
ax2.spines["top"].set_visible(False)
bars2 = ax2.bar(x + w / 2, q9["effective_discount_pct"], w,
                color=NEGATIVE_COLOR, edgecolor="white", linewidth=1.2, label="Effective Discount %")
ax.set_title("Promotion Performance: Net Revenue vs Discount Rate",
             fontsize=14, fontweight="bold", color="#2c3e50", pad=14)
ax.set_ylabel("Net Revenue (₹L)", fontsize=11, color=LINE_COLOR)
ax2.set_ylabel("Effective Discount %", fontsize=11, color=NEGATIVE_COLOR)
ax.set_xticks(x)
ax.set_xticklabels(q9["promotion_name"], rotation=30, ha="right", fontsize=9)
ax.yaxis.set_major_formatter(plt.FuncFormatter(lambda v, _: f"₹{v:.1f}L"))
ax2.yaxis.set_major_formatter(plt.FuncFormatter(lambda v, _: f"{v:.0f}%"))
lines1 = mpatches.Patch(color=LINE_COLOR,     label="Net Revenue")
lines2 = mpatches.Patch(color=NEGATIVE_COLOR, label="Discount Rate")
ax.legend(handles=[lines1, lines2], fontsize=10, frameon=False, loc="upper right")
plt.tight_layout()
plt.savefig("visuals/q9_promotion_performance.png", dpi=150, bbox_inches="tight", facecolor="white")
plt.close()
print("  Saved: visuals/q9_promotion_performance.png")


# ── Q14: Month-over-month growth rate ─────────────────────────────────────────

Q14_SQL = """
WITH monthly_revenue AS (
    SELECT
        DATE_TRUNC('month', so.order_date)::date AS sales_month,
        SUM(soi.net_sales_value)                  AS monthly_revenue
    FROM sales_orders so
    JOIN sales_order_items soi ON so.order_id = soi.order_id
    WHERE so.order_date >= DATE '2025-01-01'
      AND so.order_date < DATE '2026-01-01'
    GROUP BY DATE_TRUNC('month', so.order_date)
),
with_lag AS (
    SELECT
        sales_month,
        monthly_revenue,
        LAG(monthly_revenue) OVER (ORDER BY sales_month) AS prev_revenue
    FROM monthly_revenue
)
SELECT
    sales_month,
    ROUND(monthly_revenue, 2) AS monthly_revenue,
    ROUND((monthly_revenue - prev_revenue) * 100.0 / NULLIF(prev_revenue, 0), 2) AS mom_growth_pct
FROM with_lag
WHERE prev_revenue IS NOT NULL
ORDER BY sales_month;
"""

print("Running Q14...")
q14 = query(Q14_SQL)
q14.to_csv("outputs/q14_mom_growth.csv", index=False)

fig, ax = plt.subplots(figsize=(12, 6))
fig.patch.set_facecolor("white")
clean_ax(ax)

months_str = q14["sales_month"].astype(str).str[:7]
colors = [POSITIVE_COLOR if v >= 0 else NEGATIVE_COLOR for v in q14["mom_growth_pct"]]
bars = ax.bar(months_str, q14["mom_growth_pct"], color=colors, edgecolor="white", linewidth=1.2)
ax.axhline(0, color="#2c3e50", linewidth=0.9, linestyle="--")

for bar, val in zip(bars, q14["mom_growth_pct"]):
    offset = 0.3 if val >= 0 else -0.8
    ax.text(bar.get_x() + bar.get_width() / 2, val + offset,
            f"{val:+.1f}%", ha="center", fontsize=9, fontweight="bold", color="#2c3e50")

ax.set_title("Month-over-Month Revenue Growth — Festive Surge and Post-Diwali Drop",
             fontsize=14, fontweight="bold", color="#2c3e50", pad=14)
ax.set_xlabel("Month", fontsize=11)
ax.set_ylabel("MoM Growth (%)", fontsize=11)
ax.yaxis.set_major_formatter(plt.FuncFormatter(lambda v, _: f"{v:+.0f}%"))
ax.tick_params(axis="x", rotation=45)
pos_p = mpatches.Patch(color=POSITIVE_COLOR, label="Growth")
neg_p = mpatches.Patch(color=NEGATIVE_COLOR, label="Decline")
ax.legend(handles=[pos_p, neg_p], fontsize=10, frameon=False)
plt.tight_layout()
plt.savefig("visuals/q14_mom_growth.png", dpi=150, bbox_inches="tight", facecolor="white")
plt.close()
print("  Saved: visuals/q14_mom_growth.png")

print("\nDone. CSVs → outputs/   Charts → visuals/")
