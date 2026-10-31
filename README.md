# ⚡ Electricity Bill Calculator

A production-ready, object-oriented Flutter application designed to compute utility electricity bills based on dynamic, slab-based tariff structures. Built using clean architecture principles in Dart, this project separates core mathematical billing logic from presentation widgets to achieve high testability, scalability, and maintainability.

🌐 **Live Demo:** <https://electricity-qs89.onrender.com/>

---

## 📌 Executive Summary

Modern power utility companies charge consumers using **tiered or slab-based pricing structures**, where the price per unit increases (or varies) depending on total monthly usage. Calculating these charges manually or with monolithic code can lead to logic bugs and maintenance challenges. 

This project solves that problem by establishing a clear **Object-Oriented Programming (OOP)** domain model that encapsulates individual tariff rules, tracks unit ranges, computes progressive cost breakdowns, and presents the results through a modern, responsive **Material 3 Flutter user interface**.

---

## 🏗️ Detailed Architecture & System Design

The application follows the **Separation of Concerns (SoC)** principle, ensuring that business logic has zero dependencies on Flutter UI code. This allows the core calculation engine to be extracted, reused in command-line scripts, or unit-tested independently of the UI framework.

```text
               +-----------------------------------+
               |       ElectricityBillScreen       |
               |        (Flutter UI Layer)         |
               +-----------------------------------+
                                 |
                                 v
               +-----------------------------------+
               |    ElectricityBillCalculator      |
               |      (Business Logic Engine)      |
               +-----------------------------------+
                                 |
                 +---------------+---------------+
                 |                               |
                 v                               v
       +-------------------+           +-------------------+
       |    TariffSlab     |           |  ElectricityBill  |
       |  (Domain Model)   |           |   (Output Model)  |
       +-------------------+           +-------------------+
```

### Class Responsibilities & Design Patterns

#### 1. `TariffSlab` (Domain Model)
* **Purpose:** Represents an individual pricing tier.
* **Encapsulation:** Holds state for `minUnits`, `maxUnits`, and `ratePerUnit`.
* **Behavior:** Contains the `calculateSlabCost(double totalUnits)` method, which determines exactly how many units of a given consumption value fall within its boundary and returns the corresponding charge.

#### 2. `ElectricityBill` (Output DTO / Data Class)
* **Purpose:** Serves as an immutable data structure returned after calculation.
* **Encapsulation:** Houses the result fields: `unitsConsumed`, `energyCharge`, `fixedCharge`, and `totalAmount`.

#### 3. `ElectricityBillCalculator` (Service Layer / Engine)
* **Purpose:** Manages the collection of tariff slabs and base fees.
* **Behavior:** Implements `calculateBill(double units)`. It iterates across ordered slabs, aggregates partial energy charges, adds base fixed charges, performs validation, and constructs a final `ElectricityBill` instance.

#### 4. `ElectricityBillScreen` (Presentation Layer)
* **Purpose:** Manages user input, validation states, button actions, and summary card displays.
* **Behavior:** Listens for user text input, triggers calculation on `ElectricityBillCalculator`, and visually maps outputs using Flutter Material 3 widgets.

---

## 📁 Repository & Directory Structure

```text
FlutterProject/
│
├── .github/                      # CI/CD workflow configurations (if applicable)
├── build/                        # Compiled production artifacts (Web, APK, binaries)
├── web/                          # Web app entry assets (index.html, manifest.json, icons)
│
├── lib/                          # Core Dart Source Code
│   ├── models/                   # Pure Dart Domain Models (No Flutter imports)
│   │   ├── tariff_slab.dart      # Defines unit boundaries and slab calculations
│   │   └── electricity_bill.dart # Immutable billing result data class
│   │
│   ├── services/                 # Business Logic Services
│   │   └── bill_calculator.dart  # Evaluates inputs against configured slabs
│   │
│   └── main.dart                 # Application entrypoint & Material 3 UI widgets
│
├── test/                         # Automated Tests
│   └── bill_calculator_test.dart # Unit tests verifying slab mathematical accuracy
│
├── .gitignore                    # Version control exclusion rules
├── Dockerfile                    # Containerization script for Render deployment
├── pubspec.yaml                  # Project dependencies and asset declarations
└── README.md                     # Comprehensive project documentation
```

---

## 💡 Mathematical Logic & Slab Step-Through

The calculator uses **incremental tier computation**. Rather than applying a single rate to the entire consumption, units are partitioned across defined brackets.

### Standard Slab Tariff Schedule:

| Slab Tier | Range (kWh) | Unit Rate ($) | Notes |
| :--- | :--- | :--- | :--- |
| **Tier 1** | `0 - 100` | **$3.50** | Baseline lifeline rate |
| **Tier 2** | `100 - 300` | **$5.25** | Standard residential rate |
| **Tier 3** | `300+` | **$7.80** | High consumption penalty rate |
| **Fixed Fee** | N/A | **$50.00** | Base grid connection service fee |

---

### Walkthrough Calculation Example:
**Input Consumption:** `250.0 kWh`

1. **Tier 1 Processing (`0` to `100 kWh`):**
   * $\text{Applicable Units} = \min(250, 100) - 0 = 100\text{ kWh}$
   * $\text{Cost} = 100 \times \$3.50 = \mathbf{\$350.00}$

2. **Tier 2 Processing (`100` to `300 kWh`):**
   * $\text{Applicable Units} = \min(250, 300) - 100 = 150\text{ kWh}$
   * $\text{Cost} = 150 \times \$5.25 = \mathbf{\$787.50}$

3. **Tier 3 Processing (`300+ kWh`):**
   * Consumption ($250$) does not exceed $300\text{ kWh}$.
   * $\text{Cost} = 0 \times \$7.80 = \mathbf{\$0.00}$

4. **Totals Aggregation:**
   * $\text{Energy Charge Total} = \$350.00 + \$787.50 = \mathbf{\$1,137.50}$
   * $\text{Fixed Connection Charge} = \mathbf{\$50.00}$
   * $\text{Final Bill Amount Payable} = \$1,137.50 + \$50.00 = \mathbf{\$1,187.50}$

---

## 🌐 Production Deployment on Render

This project is deployed as a Web application hosted on **Render**.

### Deployment Settings (Render Static Site / Web Service)
* **Repository:** `https://github.com/SugamyaRuby-07/FlutterProject`
* **Build Command:**
  ```bash
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 && export PATH="$PATH:$(pwd)/flutter/bin" && flutter pub get && flutter build web --release
  ```
* **Publish Directory:**
  ```text
  build/web
  ```

---

## 🚀 Local Installation & Development

### Prerequisites
* [Flutter SDK](https://docs.flutter.dev/get-started/install) (v3.0.0+)
* [Dart SDK](https://dart.dev/get-dart) (v3.0.0+)
* Chrome Browser (for web testing) or an Android/iOS Emulator.

### Running the Application

1. **Clone the repository:**
   ```bash
   git clone https://github.com/SugamyaRuby-07/FlutterProject.git
   cd FlutterProject
   ```

2. **Fetch dependencies:**
   ```bash
   flutter pub get
   ```

3. **Launch in Chrome (Web):**
   ```bash
   flutter run -d chrome
   ```

4. **Run Unit Tests:**
   ```bash
   flutter test
   ```

---

## 📜 License

Distributed under the MIT License. See `LICENSE` for details.
