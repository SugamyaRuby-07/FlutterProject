# ⚡ Electricity Bill Calculator

A modern, responsive, and cross-platform **Electricity Bill Calculator** application built with **Flutter** and **Dart**. The application utilizes Object-Oriented Programming (OOP) principles to handle tier-based (slab) tariff calculations dynamically, complete with fixed charges, a detailed breakdown summary, and a clean Material 3 UI.

---

## 🌐 Live Demo

Check out the deployed application on Render:  
👉 **[Live App: Electricity Bill Calculator](https://electricity-qs89.onrender.com/)**

---

## ✨ Features

- **Slab-Based Tariff Calculation:** Computes electricity charges across custom energy slabs (e.g., 0–100 units, 100–300 units, 300+ units).
- **Clean Object-Oriented Architecture:** Decouples core tariff evaluation logic (`TariffSlab`, `ElectricityBillCalculator`) from UI presentation components.
- **Detailed Cost Breakdown:** Generates a summary of energy charges, fixed service charges, and total amount payable.
- **Robust Input Validation:** Built-in guards against invalid inputs, empty fields, and negative values.
- **Cross-Platform Support:** Ready to compile for Web, Android, iOS, Windows, macOS, and Linux.

---

## 🏗️ Project Architecture & OOP Design

The core calculation is isolated in pure Dart classes for high testability and maintainability:

- **`TariffSlab`**: Encapsulates minimum units, maximum units, and rate per unit for an individual pricing tier.
- **`ElectricityBill`**: Data class capturing total units, calculated energy charge, fixed charge, and final bill total.
- **`ElectricityBillCalculator`**: The evaluation engine that processes consumption units through configured tariff slabs.

```text
lib/
└── main.dart                      # Application entry point & Flutter Material 3 UI
