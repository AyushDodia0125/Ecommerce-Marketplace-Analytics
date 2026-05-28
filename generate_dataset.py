"""
generate_dataset.py
-------------------
Generates synthetic but realistic Indian e-commerce marketplace data.
Produces 6 CSV files inside the /data folder:
  - customers.csv
  - sellers.csv
  - products.csv
  - orders.csv
  - events.csv
  - inventory.csv

Run: python generate_dataset.py
"""

import os
import random
import numpy as np
import pandas as pd
from datetime import datetime, timedelta

random.seed(42)
np.random.seed(42)

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "data")
os.makedirs(OUTPUT_DIR, exist_ok=True)

# ── Configuration ──────────────────────────────────────────────────────────────

START_DATE = datetime(2023, 1, 1)
END_DATE   = datetime(2024, 12, 31)

N_CUSTOMERS = 5_000
N_SELLERS   = 500
N_PRODUCTS  = 2_000
N_ORDERS    = 50_000
N_EVENTS    = 200_000

INDIAN_CITIES = [
    "Mumbai", "Delhi", "Bengaluru", "Hyderabad", "Chennai",
    "Kolkata", "Pune", "Ahmedabad", "Jaipur", "Lucknow",
    "Surat", "Indore", "Bhopal", "Nagpur", "Patna",
    "Chandigarh", "Coimbatore", "Kochi", "Vadodara", "Agra",
]

CITY_STATE = {
    "Mumbai": "Maharashtra", "Pune": "Maharashtra", "Nagpur": "Maharashtra",
    "Delhi": "Delhi", "Agra": "Uttar Pradesh", "Lucknow": "Uttar Pradesh",
    "Bengaluru": "Karnataka",
    "Hyderabad": "Telangana",
    "Chennai": "Tamil Nadu", "Coimbatore": "Tamil Nadu",
    "Kolkata": "West Bengal",
    "Ahmedabad": "Gujarat", "Surat": "Gujarat", "Vadodara": "Gujarat",
    "Jaipur": "Rajasthan",
    "Indore": "Madhya Pradesh", "Bhopal": "Madhya Pradesh",
    "Patna": "Bihar",
    "Chandigarh": "Punjab",
    "Kochi": "Kerala",
}

CATEGORIES = {
    "Electronics":    ["Smartphones", "Laptops", "Earphones", "Smartwatches", "Tablets"],
    "Fashion":        ["Men Clothing", "Women Clothing", "Footwear", "Accessories", "Kids Wear"],
    "Home & Kitchen": ["Cookware", "Furniture", "Decor", "Bedding", "Appliances"],
    "Beauty":         ["Skincare", "Haircare", "Makeup", "Fragrances", "Personal Care"],
    "Sports":         ["Fitness Equipment", "Cricket", "Footwear", "Outdoor", "Yoga"],
    "Books":          ["Fiction", "Non-Fiction", "Academic", "Children", "Comics"],
    "Grocery":        ["Staples", "Snacks", "Beverages", "Dairy", "Personal Hygiene"],
}

BRANDS = {
    "Electronics":    ["Samsung", "Apple", "OnePlus", "boAt", "Mi", "Realme", "Sony"],
    "Fashion":        ["Zara", "H&M", "Myntra", "FabIndia", "W", "Biba", "Puma"],
    "Home & Kitchen": ["Prestige", "Philips", "IKEA", "Milton", "Cello", "Pigeon"],
    "Beauty":         ["Lakme", "Mamaearth", "Nykaa", "L'Oreal", "Himalaya", "Biotique"],
    "Sports":         ["Nike", "Adidas", "Decathlon", "Cosco", "SG", "Nivia"],
    "Books":          ["Penguin", "HarperCollins", "Rupa", "Westland", "Scholastic"],
    "Grocery":        ["Tata", "ITC", "Nestle", "Amul", "Britannia", "Dabur"],
}

ACQUISITION_CHANNELS = ["Organic Search", "Paid Ads", "Social Media", "Referral", "Email", "App Install"]
CUSTOMER_SEGMENTS    = ["New", "Regular", "Premium", "Inactive"]
FULFILLMENT_TYPES    = ["FBA", "Self-Ship", "Marketplace"]
ORDER_STATUSES       = ["Delivered", "Cancelled", "Returned", "Processing"]
EVENT_TYPES          = ["view", "add_to_cart", "remove_from_cart", "checkout", "purchase"]
PLATFORMS            = ["Android App", "iOS App", "Web", "Mobile Web"]


# ── Helpers ────────────────────────────────────────────────────────────────────

def rand_date(start: datetime, end: datetime) -> datetime:
    delta = end - start
    return start + timedelta(days=random.randint(0, delta.days))


def weighted_status():
    return random.choices(
        ORDER_STATUSES,
        weights=[0.78, 0.10, 0.08, 0.04],
    )[0]


def weighted_segment():
    return random.choices(
        CUSTOMER_SEGMENTS,
        weights=[0.30, 0.40, 0.15, 0.15],
    )[0]


# ── 1. Customers ───────────────────────────────────────────────────────────────

def generate_customers() -> pd.DataFrame:
    print("  Generating customers...")
    cities   = random.choices(INDIAN_CITIES, k=N_CUSTOMERS)
    segments = [weighted_segment() for _ in range(N_CUSTOMERS)]

    lifetime_map = {
        "New": (1, 3), "Regular": (4, 20),
        "Premium": (15, 60), "Inactive": (1, 5),
    }

    rows = []
    for i in range(N_CUSTOMERS):
        city    = cities[i]
        seg     = segments[i]
        lo, hi  = lifetime_map[seg]
        signup  = rand_date(START_DATE, END_DATE - timedelta(days=90))
        rows.append({
            "customer_id":          i + 1,
            "city":                 city,
            "state":                CITY_STATE.get(city, "Unknown"),
            "signup_date":          signup.date(),
            "segment":              seg,
            "acquisition_channel":  random.choice(ACQUISITION_CHANNELS),
            "lifetime_orders":      random.randint(lo, hi),
        })
    df = pd.DataFrame(rows)
    df.to_csv(os.path.join(OUTPUT_DIR, "customers.csv"), index=False)
    print(f"    ✓ {len(df):,} customers saved.")
    return df


# ── 2. Sellers ─────────────────────────────────────────────────────────────────

def generate_sellers() -> pd.DataFrame:
    print("  Generating sellers...")
    rows = []
    for i in range(N_SELLERS):
        city = random.choice(INDIAN_CITIES)
        cat  = random.choice(list(CATEGORIES.keys()))
        rows.append({
            "seller_id":        i + 1,
            "city":             city,
            "state":            CITY_STATE.get(city, "Unknown"),
            "join_date":        rand_date(START_DATE - timedelta(days=365), START_DATE).date(),
            "category_focus":   cat,
            "fulfillment_type": random.choice(FULFILLMENT_TYPES),
            "seller_rating":    round(random.uniform(2.5, 5.0), 1),
            "active_listings":  random.randint(10, 500),
        })
    df = pd.DataFrame(rows)
    df.to_csv(os.path.join(OUTPUT_DIR, "sellers.csv"), index=False)
    print(f"    ✓ {len(df):,} sellers saved.")
    return df


# ── 3. Products ────────────────────────────────────────────────────────────────

def generate_products() -> pd.DataFrame:
    print("  Generating products...")
    rows = []
    for i in range(N_PRODUCTS):
        cat    = random.choice(list(CATEGORIES.keys()))
        subcat = random.choice(CATEGORIES[cat])
        brand  = random.choice(BRANDS[cat])

        # Price ranges realistic to Indian market
        mrp_ranges = {
            "Electronics": (499, 149999),
            "Fashion":      (199, 9999),
            "Home & Kitchen": (199, 29999),
            "Beauty":       (99, 4999),
            "Sports":       (199, 19999),
            "Books":        (99, 999),
            "Grocery":      (29, 999),
        }
        lo, hi = mrp_ranges[cat]
        mrp = round(random.uniform(lo, hi), -1)  # round to nearest 10

        rows.append({
            "product_id":   i + 1,
            "category":     cat,
            "subcategory":  subcat,
            "brand":        brand,
            "mrp":          mrp,
            "avg_rating":   round(random.uniform(2.8, 5.0), 1),
            "listing_date": rand_date(START_DATE - timedelta(days=365), START_DATE + timedelta(days=180)).date(),
        })
    df = pd.DataFrame(rows)
    df.to_csv(os.path.join(OUTPUT_DIR, "products.csv"), index=False)
    print(f"    ✓ {len(df):,} products saved.")
    return df


# ── 4. Orders ──────────────────────────────────────────────────────────────────

def generate_orders(customers: pd.DataFrame, sellers: pd.DataFrame, products: pd.DataFrame) -> pd.DataFrame:
    print("  Generating orders...")

    cust_ids    = customers["customer_id"].tolist()
    seller_ids  = sellers["seller_id"].tolist()
    product_ids = products["product_id"].tolist()

    # Build product → mrp lookup
    mrp_lookup = products.set_index("product_id")["mrp"].to_dict()

    rows = []
    for i in range(N_ORDERS):
        pid        = random.choice(product_ids)
        mrp        = mrp_lookup[pid]
        discount   = round(mrp * random.uniform(0.0, 0.45), 2)
        gmv        = round(mrp - discount, 2)
        status     = weighted_status()
        order_date = rand_date(START_DATE, END_DATE)

        # Seasonal boost: Oct–Dec gets 40% more orders (festival season)
        if order_date.month in [10, 11, 12] and random.random() < 0.40:
            order_date = rand_date(
                datetime(order_date.year, 10, 1),
                datetime(order_date.year, 12, 31),
            )

        rows.append({
            "order_id":       i + 1,
            "customer_id":    random.choice(cust_ids),
            "seller_id":      random.choice(seller_ids),
            "product_id":     pid,
            "order_date":     order_date.date(),
            "status":         status,
            "gmv":            gmv,
            "discount_amt":   discount,
            "delivery_days":  random.randint(1, 14) if status == "Delivered" else None,
            "return_flag":    status == "Returned",
        })

    df = pd.DataFrame(rows)
    df.to_csv(os.path.join(OUTPUT_DIR, "orders.csv"), index=False)
    print(f"    ✓ {len(df):,} orders saved.")
    return df


# ── 5. Events (Clickstream) ────────────────────────────────────────────────────

def generate_events(customers: pd.DataFrame, products: pd.DataFrame) -> pd.DataFrame:
    print("  Generating events (this takes a moment)...")

    cust_ids    = customers["customer_id"].tolist()
    product_ids = products["product_id"].tolist()

    # Funnel weights: view is most common, purchase least
    event_weights = [0.55, 0.20, 0.05, 0.12, 0.08]

    rows = []
    session_counter = 0
    for i in range(N_EVENTS):
        if i % 10 == 0:
            session_counter += 1  # new session every ~10 events
        event_ts = rand_date(START_DATE, END_DATE)
        rows.append({
            "event_id":    i + 1,
            "customer_id": random.choice(cust_ids),
            "product_id":  random.choice(product_ids),
            "event_type":  random.choices(EVENT_TYPES, weights=event_weights)[0],
            "event_ts":    event_ts.strftime("%Y-%m-%d %H:%M:%S"),
            "session_id":  f"sess_{session_counter:07d}",
            "platform":    random.choice(PLATFORMS),
        })

    df = pd.DataFrame(rows)
    df.to_csv(os.path.join(OUTPUT_DIR, "events.csv"), index=False)
    print(f"    ✓ {len(df):,} events saved.")
    return df


# ── 6. Inventory ───────────────────────────────────────────────────────────────

def generate_inventory(sellers: pd.DataFrame, products: pd.DataFrame) -> pd.DataFrame:
    print("  Generating inventory...")

    seller_ids  = sellers["seller_id"].tolist()
    product_ids = products["product_id"].tolist()

    # Each seller stocks ~30–60 unique products, sampled weekly
    rows = []
    inv_id = 1
    sample_dates = pd.date_range(START_DATE, END_DATE, freq="W").tolist()

    # Use a smaller cross to keep file size reasonable (~60K rows)
    seller_sample  = random.sample(seller_ids, 200)
    product_sample = random.sample(product_ids, 500)

    for seller_id in seller_sample:
        my_products = random.sample(product_sample, random.randint(10, 40))
        for product_id in my_products:
            for dt in random.sample(sample_dates, random.randint(4, 12)):
                units_avail = random.randint(0, 300)
                units_sold  = random.randint(0, min(units_avail, 80))
                stockout    = units_avail == 0
                rows.append({
                    "inventory_id":    inv_id,
                    "product_id":      product_id,
                    "seller_id":       seller_id,
                    "stock_date":      dt.date(),
                    "units_available": units_avail,
                    "units_sold":      units_sold,
                    "stockout_flag":   stockout,
                })
                inv_id += 1

    df = pd.DataFrame(rows)
    df.to_csv(os.path.join(OUTPUT_DIR, "inventory.csv"), index=False)
    print(f"    ✓ {len(df):,} inventory records saved.")
    return df


# ── Main ───────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    print("\n🚀 Generating Ecommerce Marketplace Dataset...\n")
    customers = generate_customers()
    sellers   = generate_sellers()
    products  = generate_products()
    orders    = generate_orders(customers, sellers, products)
    events    = generate_events(customers, products)
    inventory = generate_inventory(sellers, products)

    print("\n✅ All files written to /data:\n")
    for f in sorted(os.listdir(OUTPUT_DIR)):
        path = os.path.join(OUTPUT_DIR, f)
        size = os.path.getsize(path) / 1024
        rows = sum(1 for _ in open(path)) - 1
        print(f"   {f:<22} {rows:>8,} rows   {size:>8.1f} KB")
    print()
