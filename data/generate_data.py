"""
Route-to-Retail: FMCG Distributor Sales — Synthetic Data Generator
Populates all 7 tables for calendar year 2025.

Run AFTER executing schema/create_tables.sql on your Neon/PostgreSQL database.
Requires: psycopg2-binary, python-dotenv, faker
"""
import os
import random
from datetime import date, timedelta

import psycopg2
from psycopg2.extras import execute_batch
from dotenv import load_dotenv
from faker import Faker

load_dotenv()
DATABASE_URL = os.environ["DATABASE_URL"].strip()

if not DATABASE_URL.startswith(("postgresql://", "postgres://")):
    raise ValueError(
        f"DATABASE_URL does not look like a valid connection URL.\n"
        f"  Starts with: {DATABASE_URL[:40]!r}\n"
        f"  Expected format: postgresql://user:password@host/dbname?sslmode=require\n"
        f"  Check your .env file — the value must be on a single line with no line breaks."
    )

random.seed(42)
fake = Faker("en_IN")
Faker.seed(42)

# ── Business constants ─────────────────────────────────────────────────────────

TARGET_ITEMS     = 15_000
PROMO_APPLY_PROB = 0.95    # probability of applying a promo when one is valid (gives ~20% overall)
BATCH_SIZE       = 500

ZONE_VOLUME  = {"North": 0.30, "West": 0.28, "South": 0.23, "East": 0.19}
TIER_MULT    = {"A": 5.0, "B": 2.5, "C": 1.0}
CATEGORY_COST_RATIO = {
    "Beverages":      0.78,   # 22% gross margin — high competition
    "Packaged Foods": 0.76,   # 24% gross margin — commodity pressure
    "Home Care":      0.72,   # 28% gross margin — moderate competition
    "Personal Care":  0.66,   # 34% gross margin — brand premium
}
TIER_RETAILER_COUNT = {"A": 6, "B": 4, "C": 3}
CATEGORIES   = ["Home Care", "Personal Care", "Packaged Foods", "Beverages"]

# (tier_A_count, tier_B_count, tier_C_count) — totals to 30 distributors
# A=6, B=11, C=13 across all zones
ZONE_TIER_COUNTS = {
    "North": (2, 3, 4),   # 9 distributors
    "West":  (2, 3, 3),   # 8 distributors
    "South": (1, 3, 3),   # 7 distributors
    "East":  (1, 2, 3),   # 6 distributors
}

ZONE_CITIES = {
    "North": ["Delhi", "Lucknow", "Chandigarh", "Jaipur", "Agra", "Amritsar", "Meerut", "Varanasi", "Patiala"],
    "South": ["Chennai", "Bengaluru", "Hyderabad", "Kochi", "Coimbatore", "Mysuru", "Vijayawada", "Madurai"],
    "East":  ["Kolkata", "Bhubaneswar", "Patna", "Ranchi", "Guwahati", "Cuttack"],
    "West":  ["Mumbai", "Pune", "Ahmedabad", "Surat", "Nagpur", "Nashik", "Vadodara", "Rajkot"],
}

CHANNEL_WEIGHTS = [("General Trade", 0.60), ("Modern Trade", 0.25), ("Wholesale", 0.15)]

# ── Static master data ─────────────────────────────────────────────────────────

# (sku_name, category, brand, mrp)
# MRP ranges per spec: Home Care ₹80-450 | Personal Care ₹60-600 | Foods ₹30-350 | Beverages ₹20-250
PRODUCTS_DEF = [
    # ── Home Care (10) ──
    ("SurfMax Detergent Powder 1kg",       "Home Care",    "SurfMax",       245.00),
    ("SurfMax Liquid Detergent 500ml",      "Home Care",    "SurfMax",       185.00),
    ("SurfMax Detergent Bar 200g",          "Home Care",    "SurfMax",        85.00),
    ("HarpicPlus Toilet Cleaner 500ml",     "Home Care",    "HarpicPlus",    135.00),
    ("HarpicPlus Rim Block 50g",            "Home Care",    "HarpicPlus",     80.00),
    ("VimShine Dish Wash Bar 300g",         "Home Care",    "VimShine",       90.00),
    ("VimShine Dish Wash Liquid 500ml",     "Home Care",    "VimShine",      145.00),
    ("LizolGard Floor Cleaner 1L",          "Home Care",    "LizolGard",     220.00),
    ("LizolGard Multi-Surface Spray 500ml", "Home Care",    "LizolGard",     165.00),
    ("LizolGard Disinfectant 2L",           "Home Care",    "LizolGard",     390.00),
    # ── Personal Care (10) ──
    ("DoveCare Bathing Soap 75g",           "Personal Care", "DoveCare",      65.00),
    ("DoveCare Shampoo 180ml",              "Personal Care", "DoveCare",     185.00),
    ("DoveCare Body Lotion 200ml",          "Personal Care", "DoveCare",     260.00),
    ("PanteneGold Shampoo 340ml",           "Personal Care", "PanteneGold",  320.00),
    ("PanteneGold Conditioner 175ml",       "Personal Care", "PanteneGold",  260.00),
    ("ColgateStar Toothpaste 200g",         "Personal Care", "ColgateStar",  145.00),
    ("ColgateStar Toothbrush 2-Pack",       "Personal Care", "ColgateStar",   85.00),
    ("NiveaBlue Face Wash 100ml",           "Personal Care", "NiveaBlue",    175.00),
    ("NiveaBlue Moisturizer 75ml",          "Personal Care", "NiveaBlue",    220.00),
    ("NiveaBlue Roll-On Deodorant 50ml",    "Personal Care", "NiveaBlue",    175.00),
    # ── Packaged Foods (10) ──
    ("MaggiQuick Noodles Twin Pack",        "Packaged Foods", "MaggiQuick",    60.00),
    ("MaggiQuick Masala Oats 200g",         "Packaged Foods", "MaggiQuick",    95.00),
    ("ParleGold Krackjack 500g",            "Packaged Foods", "ParleGold",     80.00),
    ("ParleGold Monaco Light 300g",         "Packaged Foods", "ParleGold",     55.00),
    ("ParleGold Hide & Seek 150g",          "Packaged Foods", "ParleGold",     65.00),
    ("BritanniaBake Good Day 300g",         "Packaged Foods", "BritanniaBake", 75.00),
    ("BritanniaBake Marie Gold 400g",       "Packaged Foods", "BritanniaBake", 60.00),
    ("BritanniaBake NutriChoice 200g",      "Packaged Foods", "BritanniaBake", 90.00),
    ("HaldiramSnack Bhujia 400g",           "Packaged Foods", "HaldiramSnack", 110.00),
    ("HaldiramSnack Aloo Bhujia 200g",      "Packaged Foods", "HaldiramSnack",  60.00),
    # ── Beverages (10) ──
    ("ColaMax Regular 2L",                  "Beverages", "ColaMax",      90.00),
    ("ColaMax Regular 750ml",               "Beverages", "ColaMax",      40.00),
    ("ColaMax Diet 500ml",                  "Beverages", "ColaMax",      30.00),
    ("MaazaJuice Mango 1L",                 "Beverages", "MaazaJuice",   90.00),
    ("MaazaJuice Mixed Fruit 200ml",        "Beverages", "MaazaJuice",   25.00),
    ("FrootiSip Mango Drink 200ml",         "Beverages", "FrootiSip",    20.00),
    ("FrootiSip Apple Drink 200ml",         "Beverages", "FrootiSip",    20.00),
    ("BisleriPure Mineral Water 1L",        "Beverages", "BisleriPure",  25.00),
    ("BisleriPure Club Soda 500ml",         "Beverages", "BisleriPure",  25.00),
    ("BisleriPure Mineral Water 5L",        "Beverages", "BisleriPure",  80.00),
]

# (name, category, discount_pct, start_date, end_date)
# Coverage per category × PROMO_APPLY_PROB ≈ 20% of all items will carry a promotion
PROMOTIONS_DEF = [
    # Holi cluster — March
    ("Holi Home Care Bonanza",    "Home Care",      8.0,  date(2025,  3,  1), date(2025,  3, 31)),
    ("Holi Personal Care Offer",  "Personal Care", 10.0,  date(2025,  3,  5), date(2025,  3, 31)),
    # Summer Beverages — April–June (aligns with Beverages 1.6× season)
    ("Summer Beverages Fest",     "Beverages",      7.0,  date(2025,  4,  1), date(2025,  6, 30)),
    # Mid-year push — July
    ("Mid-Year Foods Push",       "Packaged Foods", 8.0,  date(2025,  7,  1), date(2025,  7, 31)),
    ("Monsoon Personal Care",     "Personal Care",  6.0,  date(2025,  7,  1), date(2025,  8, 15)),
    # Dussehra / Diwali cluster — October–November
    ("Dussehra Packaged Foods",   "Packaged Foods",10.0,  date(2025, 10,  1), date(2025, 10, 31)),
    ("Diwali Beverages Bonanza",  "Beverages",     12.0,  date(2025, 10, 20), date(2025, 11, 30)),
    ("Festive Home Care Offer",   "Home Care",      9.0,  date(2025, 11,  1), date(2025, 11, 30)),
]

# ── Name generators ────────────────────────────────────────────────────────────

_SURNAMES = [
    "Sharma", "Gupta", "Singh", "Patel", "Mehta", "Jain", "Agarwal",
    "Reddy", "Iyer", "Nair", "Pillai", "Bose", "Das", "Roy", "Choudhury",
    "Verma", "Tiwari", "Malhotra", "Sethi", "Khanna", "Mishra", "Yadav",
    "Pandey", "Joshi", "Dubey", "Srivastava", "Saxena", "Bansal", "Kapoor",
]

_DIST_SUFFIXES = ["Traders", "Distributors", "Enterprises", "Agency", "Trading Co.", "Agencies"]

_RETAIL_TEMPLATES = [
    lambda s, c: f"New {s} General Store",
    lambda s, c: f"{s} Kirana & Provisions",
    lambda s, c: f"{c} Super Mart",
    lambda s, c: f"{s} Wholesale Depot",
    lambda s, c: f"Shree {s} Stores",
    lambda s, c: f"{s} Brothers Mart",
    lambda s, c: f"{s} & Co. Retailers",
    lambda s, c: f"Jai {s} Medical & General",
]


def rand_distributor_name():
    s = random.choice(_SURNAMES)
    sfx = random.choice(_DIST_SUFFIXES)
    return f"{s} & Sons {sfx}"


def rand_retailer_name(city):
    s = random.choice(_SURNAMES)
    fn = random.choice(_RETAIL_TEMPLATES)
    return fn(s, city)


def rand_channel():
    channels, weights = zip(*CHANNEL_WEIGHTS)
    return random.choices(channels, weights=weights, k=1)[0]


# ── Seasonality ────────────────────────────────────────────────────────────────

def seasonality_mult(category: str, month: int) -> float:
    if category == "Beverages" and 4 <= month <= 6:
        return 1.6
    if category in ("Packaged Foods", "Personal Care") and 9 <= month <= 11:
        return 1.4
    if category == "Home Care":
        return random.uniform(0.9, 1.1)
    return 1.0


# ── Insert helpers ─────────────────────────────────────────────────────────────

def insert_zones(cur) -> dict:
    for zone in ["North", "South", "East", "West"]:
        cur.execute(
            "INSERT INTO zones(zone_name) VALUES (%s) ON CONFLICT (zone_name) DO NOTHING",
            (zone,),
        )
    cur.execute("SELECT zone_id, zone_name FROM zones")
    return {name: zid for zid, name in cur.fetchall()}


def insert_products(cur) -> list:
    rows = []
    for sku, cat, brand, mrp in PRODUCTS_DEF:
        trade = round(mrp * 0.80, 2)
        cost  = round(trade * CATEGORY_COST_RATIO[cat], 2)
        rows.append((sku, cat, brand, mrp, trade, cost))
    execute_batch(cur, """
        INSERT INTO products(sku_name, category, brand, mrp, trade_price, cost_price)
        VALUES (%s, %s, %s, %s, %s, %s)
    """, rows)
    cur.execute("SELECT product_id, category, trade_price FROM products ORDER BY product_id")
    return [
        {"product_id": pid, "category": cat, "trade_price": float(tp)}
        for pid, cat, tp in cur.fetchall()
    ]


def insert_promotions(cur) -> list:
    execute_batch(cur, """
        INSERT INTO promotions(promotion_name, category, discount_percent, start_date, end_date)
        VALUES (%s, %s, %s, %s, %s)
    """, PROMOTIONS_DEF)
    cur.execute("""
        SELECT promotion_id, category, discount_percent, start_date, end_date
        FROM promotions ORDER BY promotion_id
    """)
    return [
        {"promotion_id": pid, "category": cat,
         "discount_percent": float(dp), "start_date": sd, "end_date": ed}
        for pid, cat, dp, sd, ed in cur.fetchall()
    ]


def insert_distributors(cur, zone_ids: dict) -> list:
    distributors = []
    for zone_name, (na, nb, nc) in ZONE_TIER_COUNTS.items():
        tier_list = ["A"] * na + ["B"] * nb + ["C"] * nc
        cities = ZONE_CITIES[zone_name][:]
        random.shuffle(cities)
        for i, tier in enumerate(tier_list):
            city = cities[i % len(cities)]
            name = rand_distributor_name()
            cur.execute("""
                INSERT INTO distributors(distributor_name, zone_id, tier, city, active_status)
                VALUES (%s, %s, %s, %s, TRUE) RETURNING distributor_id
            """, (name, zone_ids[zone_name], tier, city))
            did = cur.fetchone()[0]
            distributors.append({"distributor_id": did, "zone_name": zone_name,
                                  "tier": tier, "city": city})
    return distributors


def insert_retailers(cur, distributors: list) -> dict:
    retailer_map = {}
    for d in distributors:
        did, city = d["distributor_id"], d["city"]
        retailer_map[did] = []
        for _ in range(TIER_RETAILER_COUNT[d["tier"]]):
            name    = rand_retailer_name(city)
            channel = rand_channel()
            cur.execute("""
                INSERT INTO retailers(retailer_name, distributor_id, city, channel_type, active_status)
                VALUES (%s, %s, %s, %s, TRUE) RETURNING retailer_id
            """, (name, did, city, channel))
            retailer_map[did].append(cur.fetchone()[0])
    return retailer_map


# ── Target calculation ─────────────────────────────────────────────────────────

def assign_targets(distributors: list) -> None:
    """Stamp each distributor dict with target_items based on zone volume × tier weight."""
    for zone_name in ZONE_VOLUME:
        zone_dists   = [d for d in distributors if d["zone_name"] == zone_name]
        zone_items   = round(TARGET_ITEMS * ZONE_VOLUME[zone_name])
        total_weight = sum(TIER_MULT[d["tier"]] for d in zone_dists)
        for d in zone_dists:
            d["target_items"] = round(zone_items * TIER_MULT[d["tier"]] / total_weight)


# ── Main order + item generator ────────────────────────────────────────────────

def generate_orders_and_items(conn, distributors, retailer_map, products, promotions) -> int:
    # Build fast lookups
    cat_products   = {}
    for p in products:
        cat_products.setdefault(p["category"], []).append(p)

    cat_promotions = {}
    for promo in promotions:
        cat_promotions.setdefault(promo["category"], []).append(promo)

    item_buffer  = []
    total_items  = 0

    with conn.cursor() as cur:
        for dist in distributors:
            did            = dist["distributor_id"]
            target         = dist["target_items"]
            retailers      = retailer_map[did]
            items_for_dist = 0

            while items_for_dist < target:
                retailer_id = random.choice(retailers)
                order_date  = date(2025, 1, 1) + timedelta(days=random.randint(0, 364))

                cur.execute(
                    "INSERT INTO sales_orders(retailer_id, order_date) VALUES (%s, %s) RETURNING order_id",
                    (retailer_id, order_date),
                )
                order_id = cur.fetchone()[0]

                n_items   = random.randint(2, 6)
                used_pids = set()

                for _ in range(n_items):
                    if items_for_dist >= target:
                        break

                    # Pick a product, avoiding duplicates within the same order
                    category = random.choice(CATEGORIES)
                    prods    = cat_products[category]
                    prod     = random.choice(prods)
                    for _attempt in range(8):
                        if prod["product_id"] not in used_pids:
                            break
                        prod = random.choice(prods)
                    used_pids.add(prod["product_id"])

                    # Seasonality-adjusted quantity
                    base_qty = random.randint(5, 30)
                    qty      = max(1, round(base_qty * seasonality_mult(category, order_date.month)))

                    # Promotion (only attach when a valid promo exists for this category + date)
                    promo_id     = None
                    discount_pct = 0.0
                    if random.random() < PROMO_APPLY_PROB:
                        valid = [
                            p for p in cat_promotions.get(category, [])
                            if p["start_date"] <= order_date <= p["end_date"]
                        ]
                        if valid:
                            chosen       = random.choice(valid)
                            promo_id     = chosen["promotion_id"]
                            discount_pct = chosen["discount_percent"]

                    # Financial values
                    tp       = prod["trade_price"]
                    gross    = round(qty * tp, 2)
                    discount = round(qty * tp * discount_pct / 100, 2) if promo_id else 0.0
                    net      = round(gross - discount, 2)

                    item_buffer.append((order_id, prod["product_id"], promo_id,
                                        qty, gross, discount, net))
                    items_for_dist += 1
                    total_items    += 1

                    if len(item_buffer) >= BATCH_SIZE:
                        execute_batch(cur, """
                            INSERT INTO sales_order_items
                              (order_id, product_id, promotion_id, quantity_units,
                               gross_sales_value, discount_value, net_sales_value)
                            VALUES (%s, %s, %s, %s, %s, %s, %s)
                        """, item_buffer)
                        conn.commit()
                        print(f"  ↳ {total_items:>7,} items inserted...")
                        item_buffer.clear()

        # Flush remainder
        if item_buffer:
            execute_batch(cur, """
                INSERT INTO sales_order_items
                  (order_id, product_id, promotion_id, quantity_units,
                   gross_sales_value, discount_value, net_sales_value)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
            """, item_buffer)
            conn.commit()
            print(f"  ↳ {total_items:>7,} items inserted (final flush).")

    return total_items


# ── Row-count verification ─────────────────────────────────────────────────────

def print_row_counts(conn) -> None:
    tables = [
        "zones", "distributors", "retailers", "products",
        "promotions", "sales_orders", "sales_order_items",
    ]
    print("\n── Final row counts ──────────────────────────────────")
    with conn.cursor() as cur:
        for t in tables:
            cur.execute(f"SELECT COUNT(*) FROM {t}")
            n = cur.fetchone()[0]
            print(f"  {t:<25} {n:>8,}")

    # Quick promotion coverage check
    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM sales_order_items WHERE promotion_id IS NOT NULL")
        promo_count = cur.fetchone()[0]
        cur.execute("SELECT COUNT(*) FROM sales_order_items")
        total       = cur.fetchone()[0]
        pct         = 100 * promo_count / total if total else 0
        print(f"\n  Promotion coverage: {promo_count:,} / {total:,} items  ({pct:.1f}%)")
        print("  (Target: ~20%)")


# ── Entry point ────────────────────────────────────────────────────────────────

def main():
    print("Connecting to database...")
    conn = psycopg2.connect(DATABASE_URL)
    conn.autocommit = False

    try:
        with conn.cursor() as cur:
            print("Inserting zones...")
            zone_ids = insert_zones(cur)
            conn.commit()
            print(f"  {len(zone_ids)} zones ready.")

            print("Inserting products (40 SKUs)...")
            products = insert_products(cur)
            conn.commit()
            print(f"  {len(products)} products inserted.")

            print("Inserting promotions (8)...")
            promotions = insert_promotions(cur)
            conn.commit()
            print(f"  {len(promotions)} promotions inserted.")

            print("Inserting distributors (30)...")
            distributors = insert_distributors(cur, zone_ids)
            conn.commit()
            print(f"  {len(distributors)} distributors inserted.")

            print("Inserting retailers (120)...")
            retailer_map = insert_retailers(cur, distributors)
            conn.commit()
            total_ret = sum(len(v) for v in retailer_map.values())
            print(f"  {total_ret} retailers inserted.")

        print("Calculating item targets per distributor...")
        assign_targets(distributors)
        target_summary = {d["zone_name"]: 0 for d in distributors}
        for d in distributors:
            target_summary[d["zone_name"]] += d["target_items"]
        for zone, items in sorted(target_summary.items()):
            pct = 100 * items / sum(target_summary.values())
            print(f"  {zone:<6} target: {items:>5,} items  ({pct:.1f}%)")

        print(f"\nGenerating ~{TARGET_ITEMS:,} sales order items in batches of {BATCH_SIZE}...")
        total = generate_orders_and_items(conn, distributors, retailer_map, products, promotions)
        print(f"\n  Done — {total:,} items generated.")

        print_row_counts(conn)

    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
        print("\nConnection closed.")


if __name__ == "__main__":
    main()
