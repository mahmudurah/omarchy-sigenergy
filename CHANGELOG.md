# Changelog

## 1.1.0 (2026-11-24)
- Added 3-tier color coding for Battery State of Charge across the bar pill, popup card hero, and progress bar:
  - **Red** (`#e5534b`) when SoC `< 20%`
  - **Amber** (`#e5a93c`) when SoC `20% – 50%`
  - **Green** (`#4cc38a`) when SoC `> 50%`
- Upgraded the bar pill to a multi-segment layout so Solar and Home Load stay in theme foreground while the Home Battery indicator highlights its charge tier.

## 1.0.0 (2026-11-21)
- Initial release: Omarchy bar widget and popup card for Sigenergy (SigenStor / Sigen Hybrid) systems over local Modbus TCP.
- Live Solar (PV), Home Load, Grid power, Battery SoC/SoH, cell temperature, and daily energy breakdown.
